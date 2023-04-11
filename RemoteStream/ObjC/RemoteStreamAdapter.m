//
//  Copyright 2020-2023 Brian Keith Smith
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
//  RemoteStreamAdapter.m
//  RemoteStream
//
//  Created by Brian Smith on 10/3/20.
//

#import "RemoteStreamAdapter.h"
#if TARGET_OS_IOS
#include "gst_ios_init.h"
#endif
#include <gst/gst.h>
#include <os/log.h>

@interface RemoteStreamAdapter ()
@property NSString* location;
@property GstElement* pipeline;
@property GstElement* element;
@property GstElement* rtspSource;
@property GstElement* rtpDepay;
@property GstElement* parse;
@property GstElement* decoder;
@property GstElement* dataSink;
@property GstElement* fakeSink;
@property GstElement* videoConvert;

@property GMainContext* context;
@property GMainLoop* mainLoop;

@property(nonatomic) BOOL logSamples;
@property(nonatomic) void (^sampleHandler)(void *, NSUInteger, NSInteger, NSInteger);
@end

@implementation RemoteStreamAdapter
+ (void)initialize {
#if TARGET_OS_IOS
    gst_ios_init();
#elif TARGET_OS_MAC
    gst_init(NULL, NULL);
#endif
}

- (instancetype)initWithLocation:(NSString*)location sampleHandler:(void (^)(void *, NSUInteger, NSInteger, NSInteger))handler {
    self.location = location;
    self.sampleHandler = handler;
    self.logSamples = YES;
    
    return self;
}

- (void)connect {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self buildStream];
    });
}

- (void)disconnect {
    if (self.mainLoop) {
        g_main_loop_quit(self.mainLoop);
    }
}

- (void)play {
    if(gst_element_set_state(self.pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        os_log(OS_LOG_DEFAULT, "Failed to play stream.");
    }
}

- (void)pause {
    if(gst_element_set_state(self.pipeline, GST_STATE_PAUSED) == GST_STATE_CHANGE_FAILURE) {
        os_log(OS_LOG_DEFAULT, "Failed to pause stream.");
    }
}

static GstFlowReturn processSample(GstElement* element, RemoteStreamAdapter* self) {
    GstSample *sample;
    /* Retrieve the buffer */
    g_signal_emit_by_name (element, "pull-sample", &sample);
    if (sample) {
        gint width, height;
        
        GstCaps *capabilities = gst_sample_get_caps(sample);
        GstStructure *capabilitiesStructure = gst_caps_get_structure(capabilities, 0);
        gboolean result = FALSE;
        result = gst_structure_get_int(capabilitiesStructure, "width", &width);
        result |= gst_structure_get_int(capabilitiesStructure, "height", &height);
        
        if (!result) {
            if (self->_logSamples) os_log(OS_LOG_DEFAULT, "Unable to get capabilities");
            self->_logSamples = NO;
            return GST_FLOW_ERROR;
        }
        
        GstBuffer* buffer = gst_sample_get_buffer(sample);
        GstMapInfo map;
        if (gst_buffer_map(buffer, &map, GST_MAP_READ)) {
            self->_sampleHandler(map.data, map.size, width, height);
            gst_buffer_unmap(buffer, &map);
        }
        
        gst_sample_unref (sample);
        return GST_FLOW_OK;
    }
    
    return GST_FLOW_ERROR;
}

static void handleError(GstBus* bus, GstMessage* message, RemoteStreamAdapter* self) {
    GError *err;
    gchar *debug_info;
    gchar *message_string;

    gst_message_parse_error (message, &err, &debug_info);
    message_string = g_strdup_printf ("Error received from element %s: %s", GST_OBJECT_NAME (message->src), err->message);
    g_clear_error (&err);
    g_free (debug_info);
    os_log(OS_LOG_DEFAULT, "%s", message_string);
    g_free (message_string);
    gst_element_set_state (self->_pipeline, GST_STATE_NULL);
}

static void handleStateChange(GstBus* bus, GstMessage* message, RemoteStreamAdapter* self) {
    GstState old_state, new_state, pending_state;
    gst_message_parse_state_changed (message, &old_state, &new_state, &pending_state);
    /* Only pay attention to messages coming from the pipeline, not its children */
    if (GST_MESSAGE_SRC (message) == GST_OBJECT (self->_pipeline)) {
        gchar *message = g_strdup_printf("State changed to %s", gst_element_state_get_name(new_state));
        g_free (message);
    }
}

static void handleRtspPadAdded(GstElement* element, GstPad* pad, RemoteStreamAdapter* self) {
    GstPad* rtpDepayPad = gst_element_get_static_pad (self->_rtpDepay, "sink");
        
    if (gst_pad_is_linked (rtpDepayPad)) {
        os_log(OS_LOG_DEFAULT, "We are already linked. Ignoring.");
        goto exit;
      }
    GstPadLinkReturn state = gst_pad_link(pad, rtpDepayPad);
    if ( GST_PAD_LINK_FAILED(state) ) {
        os_log(OS_LOG_DEFAULT, "Rtsp source link failed.");
    }
    
exit:
    gst_object_unref(rtpDepayPad);
}

- (void)buildStream {
    self.rtspSource = gst_element_factory_make("rtspsrc", "rtsp-source");
    self.rtpDepay = gst_element_factory_make("rtph264depay", "depay");
    self.parse = gst_element_factory_make("h264parse", "parse");
    self.decoder = gst_element_factory_make("avdec_h264", "decoder");
    self.dataSink = gst_element_factory_make("appsink", "datasink");
    self.videoConvert = gst_element_factory_make("videoconvert", "videoconvert");
    self.fakeSink = gst_element_factory_make("fakesink", "fakesink");
    
    self.context = g_main_context_new();
    g_main_context_push_thread_default(self.context);
    
    self.pipeline = gst_pipeline_new ("test-pipeline");
    
    if ( !self.pipeline || !self.rtspSource || !self.rtpDepay || !self.parse || !self.decoder || !self.dataSink || !self.fakeSink) {
        os_log(OS_LOG_DEFAULT, "Failed to create pipeline elements.");
        return;
    }
    
    gst_bin_add_many(GST_BIN(self.pipeline),
                     self.rtspSource,
                     self.rtpDepay,
                     self.parse,
                     self.decoder,
                     self.videoConvert,
                     self.dataSink,
                     nil);
    
    
    if (!gst_element_link_many(self.rtpDepay, self.parse, self.decoder, self.videoConvert, self.dataSink, nil)) {
        os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEBUG, "Many link failed.");
        gst_object_unref(self.pipeline);
        return;
    }
    
    g_object_set(self.rtspSource, "location", self.location.UTF8String, "latency", 500, nil);
    g_signal_connect(self.rtspSource, "pad-added", (GCallback)handleRtspPadAdded, (__bridge void*)self);
    
    GstCaps* caps = gst_caps_new_simple("video/x-raw",
                                       "format", G_TYPE_STRING, "BGRA",
                                       nil);
    g_object_set(self.dataSink, "emit-signals", TRUE, "caps", caps, nil);
    gst_caps_unref(caps);
    
    g_signal_connect(self.dataSink, "new-sample", (GCallback)processSample, (__bridge void*)self);
    
    GstBus* bus = gst_element_get_bus (self.pipeline);
    GSource* bus_source = gst_bus_create_watch (bus);
    g_source_set_callback (bus_source, (GSourceFunc) gst_bus_async_signal_func, NULL, NULL);
    g_source_attach (bus_source, self.context);
    g_source_unref (bus_source);
    g_signal_connect (G_OBJECT (bus), "message::error", (GCallback)handleError, (__bridge void *)self);
    g_signal_connect (G_OBJECT (bus), "message::state-changed", (GCallback)handleStateChange, (__bridge void *)self);
    gst_object_unref (bus);

    /* Create a GLib Main Loop and set it to run */
    self.mainLoop = g_main_loop_new (self.context, FALSE);
    g_main_loop_run (self.mainLoop);
    g_main_loop_unref (self.mainLoop);
    self.mainLoop = nil;

    /* Free resources */
    g_main_context_pop_thread_default(self.context);
    g_main_context_unref (self.context);
    gst_element_set_state (self.pipeline, GST_STATE_NULL);
    gst_object_unref (self.pipeline);
}

@end
