//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////

import Foundation
import ArgumentParser

fileprivate let Version = "1.4.0"

struct MoshCommand: ParsableCommand {
  static var configuration = CommandConfiguration(
    abstract: "",
    discussion: """
      """,
    version: Version)

  @Flag(help: "Use Blink's static mosh-server bin on remote .local/blink.")
  var installStatic: Bool = false
  
  @Option(name: .shortAndLong,
          help: "Path to remote mosh-server binary.")
  var server: String?

  @Option(
    name: [.customShort("r")],
    help: "Prediction mode",
    transform: { try BKMoshPrediction(parsing: $0) })
  var predict: BKMoshPrediction?

  @Flag (
    name: [.customShort("o")]
  )
  var predictOverwrite: Bool = false
  
  @Flag var verbose: Bool = false

  @Flag (
    name: [.customShort("T")],
    help: "Do not start a TTY"
  )
  var noSshPty: Bool = false
  
  @Option(
    name: [.customShort("R")],
    help: "How to discover the IP address that the mosh-client connects to: default, remote or local",
    transform: { try BKMoshExperimentalIP(parsing: $0) }
  )
  var experimentalRemoteIP: BKMoshExperimentalIP?
  
  @Flag(exclusivity: .exclusive)
  var addressFamily: AddressFamily?
  
  // Mosh Key
  @Option(
    name: [.customShort("k")],
    help: "Use the provided server-side key for mosh connection."
  )
  var customKey: String?

  // UDP Port
  @Option(
    name: [.customShort("p")],
    help: "Use a particular server-side UDP port or port range, for example, if this is the only port that is forwarded through a firewall to the server. Otherwise, mosh will choose a port between 60000 and 61000."
  )
  var customUDPPort: String?

  // SSH Port
  @Option(
    name: [.customShort("P")],
    help: "Specifies the SSH port to initialize mosh-server on remote host."
  )
  var customSSHPort: UInt16?

  // Identity
  @Option(
    name: [.customShort("I")],
    help: .init(
      """
        Selects a file from which the identity (private key) for public key authentication is read. The default is ~/.ssh/id_dsa, ~/.ssh/id_ecdsa, ~/.ssh/id_ed25519 and ~/.ssh/id_rsa.  Identity files may also be specified on a per-host basis in the configuration pane in the Settings of Blink.
        """,
      valueName: "identity"
    )
  )
  var identityFile: String?

  // Connect to User at Host
  @Argument(help: "[user@]host[#port]",
            transform: { UserAtHostAndPort($0) })
  var userAtHostAndPort: UserAtHostAndPort
  var hostAlias: String { userAtHostAndPort.hostAlias }
  var user: String? { userAtHostAndPort.user }
  var sshPort: UInt16? {
    get { if let port = customSSHPort { port } else { userAtHostAndPort.port } }
  }

  @Argument(
    parsing: .unconditionalRemaining,
    help: .init(
      "If a <remoteCommand> is specified, it is executed on the remote host instead of a login shell",
      valueName: "remoteCommand"
    )
  )

  fileprivate var cmd: [String] = []
  var remoteExecCommand: [String] {
    get {
      if cmd.first == "--" {
        return Array(cmd.dropFirst())
      } else {
        return cmd
      }
    }
  }
  
  func validate() throws {
    if addressFamily != nil && experimentalRemoteIP != BKMoshExperimentalIPLocal {
      throw ValidationError("Address Family can only be used with 'local' IP resolution (-R).")
    }
  }
}

extension MoshCommand {
  func bkSSHHost() throws -> BKSSHHost {
    var params: [String:Any] = [:]

    if let user = self.user {
      params["user"] = user
    }

    if let port = self.sshPort {
      params["port"] = String(port)
    }

    if let identityFile = self.identityFile {
      params["identityfile"] = identityFile
    }

    if self.verbose {
      params["loglevel"] = "INFO"
    }
    // params["loglevel"] = "DEBUG"

    params["compression"] = "no"
    return try BKSSHHost(content: params)
  }
}

extension BKMoshPrediction: CustomStringConvertible {
  init(parsing: String) throws {
    switch parsing.lowercased() {
    case "adaptive":
      self = BKMoshPredictionAdaptive
    case "always":
      self = BKMoshPredictionAlways
    case "never":
      self = BKMoshPredictionNever
    case "experimental":
      self = BKMoshPredictionExperimental
    default:
      throw ValidationError("Unknown prediction mode, must be: adaptive, always, never, experimental.")
    }
  }

  public var description: String {
    switch self {
    case BKMoshPredictionAdaptive:
      "adaptive"
    case BKMoshPredictionAlways:
      "always"
    case BKMoshPredictionNever:
      "never"
    case BKMoshPredictionExperimental:
      "experimental"
    default:
      "unknown"
    }
  }
}

extension BKMoshExperimentalIP {
  init(parsing: String) throws {
    switch parsing.lowercased() {
    case "default":
      self = BKMoshExperimentalIPNone
    case "local":
      self = BKMoshExperimentalIPLocal
    case "remote":
      self = BKMoshExperimentalIPRemote
    default:
      throw ValidationError("Unknown experimental-ip mode, must be: default, local or remote.")
    }
  }
}

enum AddressFamily: String, EnumerableFlag {
  case IPv4
  case IPv6
  
  static func name(for value: AddressFamily) -> NameSpecification {
    switch value {
    case .IPv4:
      return NameSpecification([.customShort(Character("4")), .customLong("inet4")])
    case .IPv6:
      return NameSpecification([.customShort(Character("6")), .customLong("inet6")])
    }
  }
  
  static func help(for value: AddressFamily) -> ArgumentHelp? {
    switch value {
    case .IPv4:
      return "Use IPv4 only on 'local' IP resolution"
    case .IPv6:
      return "Use IPv6 only on 'local' IP resolution"
    }
  }
}
