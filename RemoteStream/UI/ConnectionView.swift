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
//  ConnectionView.swift
//  RemoteStream
//
//  Created by Brian Smith on 5/4/21.
//

import SwiftUI

public struct ConnectionView: View {
    @ObservedObject var connection: Connection
    let numberFormatter = NumberFormatter()

    public init(connection: Connection) {
        self.connection = connection
    }
    
    #if os(iOS)
    public var body: some View {
        Form {
            Section {
                VStack {
                    HStack {
                        Text("Server")
                        TextField("myserver.local", text: $connection.server)
                            .disableAutocorrection(/*@START_MENU_TOKEN@*/false/*@END_MENU_TOKEN@*/)
                            .autocapitalization(.none)
                    }
                    HStack {
                        Text("Port")
                        TextField("8888",
                                  value: $connection.port,
                                  formatter: numberFormatter)
                        .keyboardType(.numberPad)
                    }
                    HStack {
                        Text("Path")
                        TextField("path/to/stream", text: $connection.path)
                            .disableAutocorrection(/*@START_MENU_TOKEN@*/false/*@END_MENU_TOKEN@*/)
                            .autocapitalization(.none)
                    }
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("Connect") {
                        connection.isConnected = true
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
    }
    #elseif os(macOS)
    public var body: some View {
        Form(content: {
            VStack {
                HStack {
                    Text("Server")
                    TextField("myserver.local", text: $connection.server)
                        .disableAutocorrection(/*@START_MENU_TOKEN@*/false/*@END_MENU_TOKEN@*/)
                }
                HStack {
                    Text("Port")
                    TextField("8888",
                              value: $connection.port,
                              formatter: numberFormatter)
                }
                HStack {
                    Text("Path")
                    TextField("path/to/stream", text: $connection.path)
                        .disableAutocorrection(/*@START_MENU_TOKEN@*/false/*@END_MENU_TOKEN@*/)
                }
            }
            HStack {
                Spacer()
                Button("Connect") {
                    connection.isConnected = true
                }
                Spacer()
            }
        })
    }
    #endif
}

struct ConnectionView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectionView(connection: Connection())
    }
}
