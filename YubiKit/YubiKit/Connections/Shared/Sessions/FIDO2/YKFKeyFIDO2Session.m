// Copyright 2018-2019 Yubico AB
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "YKFKeyFIDO2Session.h"
#import "YKFKeyFIDO2Session+Private.h"
#import "YKFAccessoryConnectionController.h"
#import "YKFKeyFIDO2Error.h"
#import "YKFKeyAPDUError.h"
#import "YKFKeyCommandConfiguration.h"
#import "YKFLogger.h"
#import "YKFBlockMacros.h"
#import "YKFNSDataAdditions.h"
#import "YKFAssert.h"

#import "YKFFIDO2PinAuthKey.h"
#import "YKFKeyFIDO2ClientPinRequest.h"
#import "YKFKeyFIDO2ClientPinResponse.h"

#import "YKFFIDO2MakeCredentialAPDU.h"
#import "YKFFIDO2GetAssertionAPDU.h"
#import "YKFFIDO2GetNextAssertionAPDU.h"
#import "YKFFIDO2TouchPoolingAPDU.h"
#import "YKFFIDO2ClientPinAPDU.h"
#import "YKFFIDO2GetInfoAPDU.h"
#import "YKFFIDO2ResetAPDU.h"

#import "YKFKeyFIDO2GetInfoResponse+Private.h"
#import "YKFKeyFIDO2MakeCredentialResponse+Private.h"
#import "YKFKeyFIDO2GetAssertionResponse+Private.h"

#import "YKFKeyFIDO2MakeCredentialRequest+Private.h"
#import "YKFKeyFIDO2GetAssertionRequest+Private.h"

#import "YKFKeyFIDO2VerifyPinRequest.h"
#import "YKFKeyFIDO2SetPinRequest.h"
#import "YKFKeyFIDO2ChangePinRequest.h"

#import "YKFKeyFIDO2GetInfoResponse.h"
#import "YKFKeyFIDO2MakeCredentialResponse.h"
#import "YKFKeyFIDO2GetAssertionResponse.h"

#import "YKFNSDataAdditions+Private.h"
#import "YKFKeySessionError+Private.h"
#import "YKFKeyFIDO2Request+Private.h"

#import "YKFSmartCardInterface.h"
#import "YKFSelectApplicationAPDU.h"

#pragma mark - Private Response Blocks

typedef void (^YKFKeyFIDO2SessionResultCompletionBlock)
    (NSData* _Nullable response, NSError* _Nullable error);

typedef void (^YKFKeyFIDO2SessionClientPinCompletionBlock)
    (YKFKeyFIDO2ClientPinResponse* _Nullable response, NSError* _Nullable error);

typedef void (^YKFKeyFIDO2SessionClientPinSharedSecretCompletionBlock)
    (NSData* _Nullable sharedSecret, YKFCBORMap* _Nullable cosePlatformPublicKey, NSError* _Nullable error);

#pragma mark - YKFKeyFIDO2Session

@interface YKFKeyFIDO2Session()

@property (nonatomic, assign, readwrite) YKFKeyFIDO2SessionKeyState keyState;

// The cached authenticator pinToken, assigned after a successful validation.
@property NSData *pinToken;
// Keeps the state of the application selection to avoid reselecting the application.
@property BOOL applicationSelected;

@property (nonatomic, readwrite) YKFSmartCardInterface *smartCardInterface;

@end

@implementation YKFKeyFIDO2Session

+ (void)sessionWithConnectionController:(nonnull id<YKFKeyConnectionControllerProtocol>)connectionController
                               completion:(YKFKeyFIDO2SessionCompletion _Nonnull)completion {
    
    YKFKeyFIDO2Session *session = [YKFKeyFIDO2Session new];
    session.smartCardInterface = [[YKFSmartCardInterface alloc] initWithConnectionController:connectionController];

    YKFSelectApplicationAPDU *apdu = [[YKFSelectApplicationAPDU alloc] initWithApplicationName:YKFSelectApplicationAPDUNameFIDO2];
    [session.smartCardInterface selectApplication:apdu completion:^(NSData * _Nullable data, NSError * _Nullable error) {
        if (error) {
            completion(nil, error);
        } else {
            [session updateKeyState:YKFKeyFIDO2SessionKeyStateIdle];
            completion(session, nil);
        }
    }];
}

- (void)clearSessionState {
    [self clearUserVerification];
}

#pragma mark - Key State

- (void)updateKeyState:(YKFKeyFIDO2SessionKeyState)keyState {
    if (self.keyState == keyState) {
        return;
    }
    self.keyState = keyState;
}

#pragma mark - Public Requests

- (void)executeGetInfoRequestWithCompletion:(YKFKeyFIDO2SessionGetInfoCompletionBlock)completion {
    YKFParameterAssertReturn(completion);
    
    YKFKeyFIDO2Request *fido2Request = [[YKFKeyFIDO2Request alloc] init];
    fido2Request.apdu = [[YKFFIDO2GetInfoAPDU alloc] init];
    
    ykf_weak_self();
    [self executeFIDO2Request:fido2Request completion:^(NSData * data, NSError *error) {
        ykf_safe_strong_self();
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSData *cborData = [strongSelf cborFromKeyResponseData:data];
        YKFKeyFIDO2GetInfoResponse *getInfoResponse = [[YKFKeyFIDO2GetInfoResponse alloc] initWithCBORData:cborData];
        
        if (getInfoResponse) {
            completion(getInfoResponse, nil);
        } else {
            completion(nil, [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeINVALID_CBOR]);
        }
    }];
}

- (void)executeVerifyPinRequest:(YKFKeyFIDO2VerifyPinRequest *)request completion:(YKFKeyFIDO2SessionCompletionBlock)completion {
    YKFParameterAssertReturn(request);
    YKFParameterAssertReturn(request.pin);
    YKFParameterAssertReturn(completion);

    [self clearUserVerification];
    
    ykf_weak_self();
    [self executeGetSharedSecretWithCompletion:^(NSData *sharedSecret, YKFCBORMap *cosePlatformPublicKey, NSError *error) {
        ykf_safe_strong_self();
        if (error) {
            completion(error);
            return;
        }        
        YKFParameterAssertReturn(sharedSecret)
        YKFParameterAssertReturn(cosePlatformPublicKey)
        
        // Get the authenticator pinToken
        YKFKeyFIDO2ClientPinRequest *clientPinGetPinTokenRequest = [[YKFKeyFIDO2ClientPinRequest alloc] init];
        clientPinGetPinTokenRequest.pinProtocol = 1;
        clientPinGetPinTokenRequest.subCommand = YKFKeyFIDO2ClientPinRequestSubCommandGetPINToken;
        clientPinGetPinTokenRequest.keyAgreement = cosePlatformPublicKey;
        
        NSData *pinData = [request.pin dataUsingEncoding:NSUTF8StringEncoding];
        NSData *pinHash = [[pinData ykf_SHA256] subdataWithRange:NSMakeRange(0, 16)];
        clientPinGetPinTokenRequest.pinHashEnc = [pinHash ykf_aes256EncryptedDataWithKey:sharedSecret];
        
        [strongSelf executeClientPinRequest:clientPinGetPinTokenRequest completion:^(YKFKeyFIDO2ClientPinResponse *response, NSError *error) {
            if (error) {
                completion(error);
                return;
            }
            NSData *encryptedPinToken = response.pinToken;
            if (!encryptedPinToken) {
                completion([YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeINVALID_CBOR]);
                return;
            }
            
            // Cache the pinToken
            strongSelf.pinToken = [response.pinToken ykf_aes256DecryptedDataWithKey:sharedSecret];
            
            if (!strongSelf.pinToken) {
                completion([YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeINVALID_CBOR]);
            } else {
                completion(nil);
            }
        }];
    }];
}

- (void)clearUserVerification {
    if (!self.pinToken && !self.applicationSelected) {
        return;
    }
    
    YKFLogVerbose(@"Clearing FIDO2 Session user verification.");
    self.pinToken = nil;
// TODO: We can't do this anymore. Should we handle it in some other way?
//        strongSelf.applicationSelected = NO; // Force also an application re-selection.
}

- (void)executeChangePinRequest:(nonnull YKFKeyFIDO2ChangePinRequest *)request completion:(nonnull YKFKeyFIDO2SessionCompletionBlock)completion {
    YKFParameterAssertReturn(request);
    YKFParameterAssertReturn(request.pinOld);
    YKFParameterAssertReturn(request.pinNew);
    YKFParameterAssertReturn(completion);

    if (request.pinOld.length < 4 || request.pinNew.length < 4 ||
        request.pinOld.length > 255 || request.pinNew.length > 255) {
        completion([YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodePIN_POLICY_VIOLATION]);
        return;
    }
    
    ykf_weak_self();
    [self executeGetSharedSecretWithCompletion:^(NSData *sharedSecret, YKFCBORMap *cosePlatformPublicKey, NSError *error) {
        ykf_safe_strong_self();
        if (error) {
            completion(error);
            return;
        }
        YKFParameterAssertReturn(sharedSecret)
        YKFParameterAssertReturn(cosePlatformPublicKey)
        
        // Change the PIN
        YKFKeyFIDO2ClientPinRequest *changePinRequest = [[YKFKeyFIDO2ClientPinRequest alloc] init];
        NSData *oldPinData = [request.pinOld dataUsingEncoding:NSUTF8StringEncoding];
        NSData *newPinData = [[request.pinNew dataUsingEncoding:NSUTF8StringEncoding] ykf_fido2PaddedPinData];

        changePinRequest.pinProtocol = 1;
        changePinRequest.subCommand = YKFKeyFIDO2ClientPinRequestSubCommandChangePIN;
        changePinRequest.keyAgreement = cosePlatformPublicKey;

        NSData *oldPinHash = [[oldPinData ykf_SHA256] subdataWithRange:NSMakeRange(0, 16)];
        changePinRequest.pinHashEnc = [oldPinHash ykf_aes256EncryptedDataWithKey:sharedSecret];

        changePinRequest.pinEnc = [newPinData ykf_aes256EncryptedDataWithKey:sharedSecret];
        
        NSMutableData *pinAuthData = [NSMutableData dataWithData:changePinRequest.pinEnc];
        [pinAuthData appendData:changePinRequest.pinHashEnc];
        changePinRequest.pinAuth = [[pinAuthData ykf_fido2HMACWithKey:sharedSecret] subdataWithRange:NSMakeRange(0, 16)];
        
        [strongSelf executeClientPinRequest:changePinRequest completion:^(YKFKeyFIDO2ClientPinResponse *response, NSError *error) {
            if (error) {
                completion(error);
                return;
            }
            // clear the cached pin token.
            strongSelf.pinToken = nil;
            completion(nil);
        }];
    }];
}

- (void)executeSetPinRequest:(nonnull YKFKeyFIDO2SetPinRequest *)request completion:(nonnull YKFKeyFIDO2SessionCompletionBlock)completion {
    YKFParameterAssertReturn(request);
    YKFParameterAssertReturn(request.pin);
    YKFParameterAssertReturn(completion);

    if (request.pin.length < 4 || request.pin.length > 255) {
        completion([YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodePIN_POLICY_VIOLATION]);
        return;
    }
    
    ykf_weak_self();
    [self executeGetSharedSecretWithCompletion:^(NSData *sharedSecret, YKFCBORMap *cosePlatformPublicKey, NSError *error) {
        ykf_safe_strong_self();
        if (error) {
            completion(error);
            return;
        }
        YKFParameterAssertReturn(sharedSecret)
        YKFParameterAssertReturn(cosePlatformPublicKey)
        
        // Set the new PIN
        YKFKeyFIDO2ClientPinRequest *setPinRequest = [[YKFKeyFIDO2ClientPinRequest alloc] init];
        setPinRequest.pinProtocol = 1;
        setPinRequest.subCommand = YKFKeyFIDO2ClientPinRequestSubCommandSetPIN;
        setPinRequest.keyAgreement = cosePlatformPublicKey;
        
        NSData *pinData = [[request.pin dataUsingEncoding:NSUTF8StringEncoding] ykf_fido2PaddedPinData];
        
        setPinRequest.pinEnc = [pinData ykf_aes256EncryptedDataWithKey:sharedSecret];
        setPinRequest.pinAuth = [[setPinRequest.pinEnc ykf_fido2HMACWithKey:sharedSecret] subdataWithRange:NSMakeRange(0, 16)];
        
        [strongSelf executeClientPinRequest:setPinRequest completion:^(YKFKeyFIDO2ClientPinResponse *response, NSError *error) {
            if (error) {
                completion(error);
                return;
            }
            completion(nil);
        }];
    }];
}

- (void)executeGetPinRetriesWithCompletion:(YKFKeyFIDO2SessionGetPinRetriesCompletionBlock)completion {
    YKFParameterAssertReturn(completion);
    
    YKFKeyFIDO2ClientPinRequest *pinRetriesRequest = [[YKFKeyFIDO2ClientPinRequest alloc] init];
    pinRetriesRequest.pinProtocol = 1;
    pinRetriesRequest.subCommand = YKFKeyFIDO2ClientPinRequestSubCommandGetRetries;
    
    [self executeClientPinRequest:pinRetriesRequest completion:^(YKFKeyFIDO2ClientPinResponse *response, NSError *error) {
        if (error) {
            completion(0, error);
            return;
        }
        completion(response.retries, nil);
    }];
}

- (void)executeMakeCredentialRequest:(YKFKeyFIDO2MakeCredentialRequest *)request completion:(YKFKeyFIDO2SessionMakeCredentialCompletionBlock)completion {
    YKFParameterAssertReturn(request);
    YKFParameterAssertReturn(completion);
    
    // Attach the PIN authentication if the pinToken is present.
    if (self.pinToken) {
        YKFParameterAssertReturn(request.clientDataHash);
        request.pinProtocol = 1;
        NSData *hmac = [request.clientDataHash ykf_fido2HMACWithKey:self.pinToken];
        request.pinAuth = [hmac subdataWithRange:NSMakeRange(0, 16)];
        if (!request.pinAuth) {
            completion(nil, [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeOTHER]);
        }
    }
    
    YKFFIDO2MakeCredentialAPDU *apdu = [[YKFFIDO2MakeCredentialAPDU alloc] initWithRequest:request];
    if (!apdu) {
        YKFKeySessionError *error = [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeOTHER];
        completion(nil, error);
        return;
    }
    request.apdu = apdu;
    
    ykf_weak_self();
    [self executeFIDO2Request:request completion:^(NSData *data, NSError *error) {
        ykf_safe_strong_self();
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSData *cborData = [strongSelf cborFromKeyResponseData:data];
        YKFKeyFIDO2MakeCredentialResponse *makeCredentialResponse = [[YKFKeyFIDO2MakeCredentialResponse alloc] initWithCBORData:cborData];
        
        if (makeCredentialResponse) {
            completion(makeCredentialResponse, nil);
        } else {
            completion(nil, [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeINVALID_CBOR]);
        }
    }];
}

- (void)executeGetAssertionRequest:(YKFKeyFIDO2GetAssertionRequest *)request completion:(YKFKeyFIDO2SessionGetAssertionCompletionBlock)completion {
    YKFParameterAssertReturn(request);
    YKFParameterAssertReturn(completion);
    
    // Attach the PIN authentication if the pinToken is present.
    if (self.pinToken) {
        YKFParameterAssertReturn(request.clientDataHash);
        request.pinProtocol = 1;
        NSData *hmac = [request.clientDataHash ykf_fido2HMACWithKey:self.pinToken];
        request.pinAuth = [hmac subdataWithRange:NSMakeRange(0, 16)];
        if (!request.pinAuth) {
            completion(nil, [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeOTHER]);
        }
    }
    
    YKFFIDO2GetAssertionAPDU *apdu = [[YKFFIDO2GetAssertionAPDU alloc] initWithRequest:request];
    if (!apdu) {
        YKFKeySessionError *error = [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeOTHER];
        completion(nil, error);
        return;
    }
    request.apdu = apdu;
    
    ykf_weak_self();
    [self executeFIDO2Request:request completion:^(NSData *data, NSError *error) {
        ykf_safe_strong_self();
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSData *cborData = [strongSelf cborFromKeyResponseData:data];
        YKFKeyFIDO2GetAssertionResponse *getAssertionResponse = [[YKFKeyFIDO2GetAssertionResponse alloc] initWithCBORData:cborData];
        
        if (getAssertionResponse) {
            completion(getAssertionResponse, nil);
        } else {
            completion(nil, [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeINVALID_CBOR]);
        }
    }];
}

- (void)executeGetNextAssertionWithCompletion:(YKFKeyFIDO2SessionGetAssertionCompletionBlock)completion {
    YKFParameterAssertReturn(completion);
    
    YKFKeyFIDO2Request *fido2Request = [[YKFKeyFIDO2Request alloc] init];
    fido2Request.apdu = [[YKFFIDO2GetNextAssertionAPDU alloc] init];
    
    ykf_weak_self();
    [self executeFIDO2Request:fido2Request completion:^(NSData *data, NSError *error) {
        ykf_safe_strong_self();
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSData *cborData = [strongSelf cborFromKeyResponseData:data];
        YKFKeyFIDO2GetAssertionResponse *getAssertionResponse = [[YKFKeyFIDO2GetAssertionResponse alloc] initWithCBORData:cborData];
        
        if (getAssertionResponse) {
            completion(getAssertionResponse, nil);
        } else {
            completion(nil, [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeINVALID_CBOR]);
        }
    }];
}

- (void)executeResetRequestWithCompletion:(YKFKeyFIDO2SessionCompletionBlock)completion {
    YKFParameterAssertReturn(completion);
    
    YKFKeyFIDO2Request *fido2Request = [[YKFKeyFIDO2Request alloc] init];
    fido2Request.apdu = [[YKFFIDO2ResetAPDU alloc] init];
    
    ykf_weak_self();
    [self executeFIDO2Request:fido2Request completion:^(NSData *response, NSError *error) {
        ykf_strong_self();
        if (!error) {
            [strongSelf clearUserVerification];
        }
        completion(error);
    }];
}

#pragma mark - Private Requests

- (void)executeClientPinRequest:(YKFKeyFIDO2ClientPinRequest *)request completion:(YKFKeyFIDO2SessionClientPinCompletionBlock)completion {
    YKFParameterAssertReturn(request);
    YKFParameterAssertReturn(completion);

    YKFFIDO2ClientPinAPDU *apdu = [[YKFFIDO2ClientPinAPDU alloc] initWithRequest:request];
    if (!apdu) {
        YKFKeySessionError *error = [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeOTHER];
        completion(nil, error);
        return;
    }
    request.apdu = apdu;
    
    ykf_weak_self();
    [self executeFIDO2Request:request completion:^(NSData *data, NSError *error) {
        ykf_safe_strong_self();
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSData *cborData = [strongSelf cborFromKeyResponseData:data];
        YKFKeyFIDO2ClientPinResponse *clientPinResponse = nil;
        
        // In case of Set/Change PIN no CBOR payload is returned.
        if (cborData.length) {
            clientPinResponse = [[YKFKeyFIDO2ClientPinResponse alloc] initWithCBORData:cborData];
        }
        
        if (clientPinResponse) {
            completion(clientPinResponse, nil);
        } else {
            if (cborData.length) {
                completion(nil, [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeINVALID_CBOR]);
            } else {
                completion(nil, nil);
            }
        }
    }];
}

- (void)executeGetSharedSecretWithCompletion:(YKFKeyFIDO2SessionClientPinSharedSecretCompletionBlock)completion {
    YKFParameterAssertReturn(completion);
    
    // Generate the platform key.
    YKFFIDO2PinAuthKey *platformKey = [[YKFFIDO2PinAuthKey alloc] init];
    if (!platformKey) {
        completion(nil, nil, [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeOTHER]);
        return;
    }
    YKFCBORMap *cosePlatformPublicKey = platformKey.cosePublicKey;
    if (!cosePlatformPublicKey) {
        completion(nil, nil, [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeOTHER]);
        return;
    }
    
    // Get the authenticator public key.
    YKFKeyFIDO2ClientPinRequest *clientPinKeyAgreementRequest = [[YKFKeyFIDO2ClientPinRequest alloc] init];
    clientPinKeyAgreementRequest.pinProtocol = 1;
    clientPinKeyAgreementRequest.subCommand = YKFKeyFIDO2ClientPinRequestSubCommandGetKeyAgreement;
    clientPinKeyAgreementRequest.keyAgreement = cosePlatformPublicKey;
    
    [self executeClientPinRequest:clientPinKeyAgreementRequest completion:^(YKFKeyFIDO2ClientPinResponse *response, NSError *error) {
        if (error) {
            completion(nil, nil, error);
            return;
        }
        NSDictionary *authenticatorKeyData = response.keyAgreement;
        if (!authenticatorKeyData) {
            completion(nil, nil, [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeINVALID_CBOR]);
            return;
        }
        YKFFIDO2PinAuthKey *authenticatorKey = [[YKFFIDO2PinAuthKey alloc] initWithCosePublicKey:authenticatorKeyData];
        if (!authenticatorKey) {
            completion(nil, nil, [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeINVALID_CBOR]);
            return;
        }
        
        // Generate the shared secret.
        NSData *sharedSecret = [platformKey sharedSecretWithAuthKey:authenticatorKey];
        if (!sharedSecret) {
            completion(nil, nil, [YKFKeyFIDO2Error errorWithCode:YKFKeyFIDO2ErrorCodeOTHER]);
            return;
        }
        sharedSecret = [sharedSecret ykf_SHA256];
        
        // Success
        completion(sharedSecret, cosePlatformPublicKey, nil);
    }];
}

#pragma mark - Request Execution

- (void)executeFIDO2Request:(YKFKeyFIDO2Request *)request completion:(YKFKeyFIDO2SessionResultCompletionBlock)completion {
    YKFParameterAssertReturn(request);
    YKFParameterAssertReturn(completion);
    
    ykf_weak_self();
    [self.smartCardInterface executeCommand:request.apdu completion:^(NSData * _Nullable data, NSError * _Nullable error) {
        ykf_safe_strong_self();

        if (data) {
            UInt8 fido2Error = [self fido2ErrorCodeFromResponseData:data];
            if (fido2Error != YKFKeyFIDO2ErrorCodeSUCCESS) {
                completion(nil, [YKFKeyFIDO2Error errorWithCode:fido2Error]);
            } else {
                completion(data, nil);
            }
        } else {
            if (error.code == YKFKeyAPDUErrorCodeFIDO2TouchRequired) {
                [strongSelf handleTouchRequired:request completion:completion];
            } else {
                completion(nil, error);
            }
        }
    }];
}

#pragma mark - Helpers

- (UInt8)fido2ErrorCodeFromResponseData:(NSData *)data {
    YKFAssertReturnValue(data.length >= 1, @"Cannot extract FIDO2 error code from the key response.", YKFKeyFIDO2ErrorCodeOTHER);
    UInt8 *payloadBytes = (UInt8 *)data.bytes;
    return payloadBytes[0];
}

- (NSData *)cborFromKeyResponseData:(NSData *)data {
    YKFAssertReturnValue(data.length >= 1, @"Cannot extract FIDO2 cbor from the key response.", nil);
    
    // discard the error byte
    return [data subdataWithRange:NSMakeRange(1, data.length - 1)];
}

- (void)handleTouchRequired:(YKFKeyFIDO2Request *)request completion:(YKFKeyFIDO2SessionResultCompletionBlock)completion {
    YKFParameterAssertReturn(request);
    YKFParameterAssertReturn(completion);
    
    if (![request shouldRetry]) {
        YKFKeySessionError *timeoutError = [YKFKeySessionError errorWithCode:YKFKeySessionErrorTouchTimeoutCode];
        completion(nil, timeoutError);

        [self updateKeyState:YKFKeyFIDO2SessionKeyStateIdle];
        return;
    }
    
    [self updateKeyState:YKFKeyFIDO2SessionKeyStateTouchKey];
    request.retries += 1;

    ykf_weak_self();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, request.retryTimeInterval * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        ykf_safe_strong_self();
        YKFKeyFIDO2Request *retryRequest = [[YKFKeyFIDO2Request alloc] init];
        retryRequest.retries = request.retries;
        retryRequest.apdu = [[YKFFIDO2TouchPoolingAPDU alloc] init];
        
        [strongSelf executeFIDO2Request:retryRequest completion:completion];
    });
}

@end
