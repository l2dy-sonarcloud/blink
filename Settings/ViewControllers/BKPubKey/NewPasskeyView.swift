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


import SwiftUI
import SSH
import CryptoKit
import AuthenticationServices
//import SwiftCBOR

@available(iOS 16.0, *)
struct NewPasskeyView: View {
  @EnvironmentObject private var _nav: Nav
  let onCancel: () -> Void
  let onSuccess: () -> Void
  
  @StateObject private var _state = NewPasskeyObservable()
  @StateObject private var _provider = RowsViewModel(baseURL: XCConfig.infoPlistConversionOpportunityURL(), additionalParams: [URLQueryItem(name: "conversion_stage", value: "security_keys_feature")])
  
  var body: some View {
    NavigationStack(path: $_state.steps) {
      List {
        Section(
          header: Text("NAME"),
          footer: Text("Default key must be named `id_ecdsa_sk`")
        ) {
          FixedTextField(
            "Enter a name for the key",
            text: $_state.keyName,
            id: "keyName",
            nextId: "keyComment",
            autocorrectionType: .no,
            autocapitalizationType: .none
          )
        }
        
        Section(header: Text("COMMENT (OPTIONAL)")) {
          FixedTextField(
            "Comment for your key",
            text: $_state.keyComment,
            id: "keyComment",
            returnKeyType: .continue,
            onReturn: _createKey,
            autocorrectionType: .no,
            autocapitalizationType: .none
          )
        }
        
        Section(
          header: Text("INFORMATION"),
          footer: Text("Passkeys are ECDSA keys that use the new Web Authentication standard for authentication. They are very new and may not be supported by all servers.\nFor more information, visit [docs.blink.sh](https://docs.blink.sh/advanced/webauthn).")
        ) { }
      }
      .listStyle(GroupedListStyle())
      .navigationBarItems(
        leading: Button("Cancel", action: onCancel),
        trailing: Button("Create", action: _createKey)
        .disabled(!_state.isValid)
      )
      .navigationBarTitle("New Passkey")
      .alert(errorMessage: $_state.errorMessage)
      .onAppear(perform: {
        FixedTextField.becomeFirstReponder(id: "keyName")
      })
      .navigationDestination(for: EarlyFeatureAccessSteps.self, destination: { step in
        switch step {
        case .Letter: EarlyFeaturesAccessLetterView(presentPlans: _state.presentPlans, rowsProvider: _provider)
        case .Plans: PlansView()
        }
      })
    }
  }
  
  
  
  private func _createKey() {
    guard let window = _nav.navController.presentedViewController?.view.window else {
      print("No window");
      return
    }
    
    _state.createKey(anchor: window, onSuccess: onSuccess)
  }
}

let domain = "blink.sh"

func rpIdWith(keyID: String) -> String {
  "\(keyID)@\(domain)"
}

fileprivate class NewPasskeyObservable: NSObject, ObservableObject {
  var onSuccess: () -> Void = {}
  @Published var steps: [EarlyFeatureAccessSteps] = []
  
  @Published var keyName = ""
  @Published var keyComment = "\(BKDefaults.defaultUserName() ?? "")@\(UIDevice.getInfoType(fromDeviceName: BKDeviceInfoTypeDeviceName) ?? "")"
  
  @Published var errorMessage = ""
  
  var isValid: Bool {
    !keyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  
  func presentPlans() {
    self.steps.append(.Plans)
  }

  
  func createKey(anchor: ASPresentationAnchor, onSuccess: @escaping () -> Void) {
    self.onSuccess = onSuccess
    errorMessage = ""
    let keyID = keyName.trimmingCharacters(in: .whitespacesAndNewlines)
    
    
    do {
      if keyID.isEmpty {
        throw KeyUIError.emptyName
      }
      
      if BKPubKey.withID(keyID) != nil {
        throw KeyUIError.duplicateName(name: keyID)
      }
      
      let challenge = Data()
      let userID = Data(keyID.utf8)
      
      let rpId = rpIdWith(keyID: keyID)
      
      let platformPubkeyProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
      
      let passkeyRequest = platformPubkeyProvider.createCredentialRegistrationRequest(
          challenge: challenge,
          name: keyID,
          userID: userID
      )
      
      let authController = ASAuthorizationController(authorizationRequests: [ passkeyRequest ] )
      authController.delegate = self
      authController.presentationContextProvider = anchor
      authController.performRequests()
    } catch {
      errorMessage = error.localizedDescription
    }

  }
}


extension UIWindow: ASAuthorizationControllerPresentationContextProviding {
  public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    self
  }
}


extension NewPasskeyObservable: ASAuthorizationControllerDelegate {
  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithError error: Error
  ) {
    self.errorMessage = error.localizedDescription
  }
  
  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    guard let registration = authorization.credential as? ASAuthorizationPublicKeyCredentialRegistration else {
      self.errorMessage = "Unexpected registration"
      return
    }
    
    guard let rawAttestationObject = registration.rawAttestationObject
    else {
      self.errorMessage = "No Attestation Object."
      return
    }
    
    guard EntitlementsManager.shared.earlyAccessFeatures.active || FeatureFlags.earlyAccessFeatures
    else {
      self.steps = [.Letter]
      return
    }
    
    let tag = registration.credentialID.base64EncodedString()
    let comment = keyComment.trimmingCharacters(in: .whitespacesAndNewlines)
    let keyID = keyName.trimmingCharacters(in: .whitespacesAndNewlines)
    
    do {
      
      try BKPubKey.addPasskey(
        id: keyID,
        rpId: rpIdWith(keyID: keyID),
        tag: tag,
        rawAttestationObject: rawAttestationObject,
        comment: comment
      )
    
      onSuccess()
    } catch {
      self.errorMessage = error.localizedDescription
    }
    
  }
  
}
