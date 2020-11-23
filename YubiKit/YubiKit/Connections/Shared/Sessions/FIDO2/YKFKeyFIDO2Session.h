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

#import <Foundation/Foundation.h>

@class YKFKeyFIDO2MakeCredentialRequest, YKFKeyFIDO2GetAssertionRequest, YKFKeyFIDO2VerifyPinRequest, YKFKeyFIDO2SetPinRequest, YKFKeyFIDO2ChangePinRequest, YKFKeyFIDO2GetInfoResponse, YKFKeyFIDO2MakeCredentialResponse, YKFKeyFIDO2GetAssertionResponse;

/**
 * ---------------------------------------------------------------------------------------------------------------------
 * @name FIDO2 Service Response Blocks
 * ---------------------------------------------------------------------------------------------------------------------
 */

/*!
 @abstract
    Response block used by FIDO2 requests which do not provide a result for the request.
 
 @param error
    In case of a failed request this parameter contains the error. If the request was successful
    this parameter is nil.
 */
typedef void (^YKFKeyFIDO2SessionCompletionBlock)
    (NSError* _Nullable error);

/*!
 @abstract
    Response block for [executeGetInfoRequestWithCompletion:] which provides the result for the execution
    of the Get Info request.
 
 @param response
    The response of the request when it was successful. In case of error this parameter is nil.
 
 @param error
    In case of a failed request this parameter contains the error. If the request was successful this
    parameter is nil.
 */
typedef void (^YKFKeyFIDO2SessionGetInfoCompletionBlock)
    (YKFKeyFIDO2GetInfoResponse* _Nullable response, NSError* _Nullable error);

/*!
 @abstract
    Response block for [executeMakeCredentialRequest:completion:] which provides the result for the execution
    of the Make Credential request.
 
 @param response
    The response of the request when it was successful. In case of error this parameter is nil.
 
 @param error
    In case of a failed request this parameter contains the error. If the request was successful this
    parameter is nil.
 */
typedef void (^YKFKeyFIDO2SessionMakeCredentialCompletionBlock)
    (YKFKeyFIDO2MakeCredentialResponse* _Nullable response, NSError* _Nullable error);

/*!
 @abstract
    Response block for [executeGetAssertionRequest:completion:] which provides the result for the execution
    of the Get Assertion request.
 
 @param response
    The response of the request when it was successful. In case of error this parameter is nil.
 
 @param error
    In case of a failed request this parameter contains the error. If the request was successful this
    parameter is nil.
 */
typedef void (^YKFKeyFIDO2SessionGetAssertionCompletionBlock)
    (YKFKeyFIDO2GetAssertionResponse* _Nullable response, NSError* _Nullable error);

/*!
 @abstract
    Response block for [executeGetPinRetriesRequestWithCompletion:] which provides available number
    of PIN retries.
 
 @param retries
    The number of PIN retries.
 
 @param error
    In case of a failed request this parameter contains the error. If the request was successful this
    parameter is nil.
 */
typedef void (^YKFKeyFIDO2SessionGetPinRetriesCompletionBlock)
    (NSUInteger retries, NSError* _Nullable error);

/**
 * ---------------------------------------------------------------------------------------------------------------------
 * @name FIDO2 Service Types
 * ---------------------------------------------------------------------------------------------------------------------
 */

/*!
 Enumerates the contextual states of the key when performing FIDO2 requests.
 */
typedef NS_ENUM(NSUInteger, YKFKeyFIDO2SessionKeyState) {
    
    /// The key is not performing any FIDO2 operation.
    YKFKeyFIDO2SessionKeyStateIdle,
    
    /// The key is executing a FIDO2 request.
    YKFKeyFIDO2SessionKeyStateProcessingRequest,
    
    /// The user must touch the key to prove a human presence which allows the key to perform the current operation.
    YKFKeyFIDO2SessionKeyStateTouchKey
};

/**
 * ---------------------------------------------------------------------------------------------------------------------
 * @name YKFKeyFIDO2ServiceProtocol
 * ---------------------------------------------------------------------------------------------------------------------
 */

NS_ASSUME_NONNULL_BEGIN

/*!
 @abstract
    Defines the interface for YKFKeyFIDO2Service.
 */
@protocol YKFKeyFIDO2SessionProtocol<NSObject>

/*!
 @abstract
    This property provides the contextual state of the key when performing FIDO2 requests.
 
 @discussion
    This property is useful for checking the status of a FIDO2 request, when the default or specified
    behaviour of the request requires UP. This property is KVO compliant and the application should
    observe it to get asynchronous state updates.
 */
@property (nonatomic, assign, readonly) YKFKeyFIDO2SessionKeyState keyState;

/*!
 @method executeGetInfoRequestWithCompletion:
 
 @abstract
    Sends to the key a FIDO2 Get Info request to retrieve the authenticator properties. The request
    is performed asynchronously on a background execution queue.
 
 @param completion
    The response block which is executed after the request was processed by the key. The completion block
    will be executed on a background thread. If the intention is to update the UI, dispatch the results
    on the main thread to avoid an UIKit assertion.
 
 @note
    This method is thread safe and can be invoked from any thread (main or a background thread).
 */
- (void)executeGetInfoRequestWithCompletion:(YKFKeyFIDO2SessionGetInfoCompletionBlock)completion;

/*!
 @method executeVerifyPinRequest:completion:
 
 @abstract
    Authenticates the session with the FIDO2 application from the key. This should be done once
    per session lifetime (while the key is plugged in) or after the user verification was cleared
    by calling [clearUserVerification].
 
 @discussion
    Once authenticated, the library will automatically attach the required PIN authentication parameters
    to the subsequent requests against the key, when necessary.
 
 @param completion
    The response block which is executed after the request was processed by the key. The completion block
    will be executed on a background thread. If the intention is to update the UI, dispatch the results
    on the main thread to avoid an UIKit assertion.
 
 @note
    This method is thread safe and can be invoked from any thread (main or a background thread).
 */
- (void)executeVerifyPinRequest:(YKFKeyFIDO2VerifyPinRequest *)request completion:(YKFKeyFIDO2SessionCompletionBlock)completion;

/*!
 @method clearUserVerification

 @abstract
    Clears the cached user verification if the user authenticated with [executeVerifyPinRequest:completion:].
 */
- (void)clearUserVerification;

/*!
 @method executeSetPinRequest:completion:
 
 @abstract
    Sets a PIN for the key FIDO2 application.
 
 @discussion
    If the key FIDO2 application has a PIN this method will return an error and change PIN should be used
    instead. The PIN can be an alphanumeric string with the length in the range [4, 255].
 
 @param completion
    The response block which is executed after the request was processed by the key. The completion block
    will be executed on a background thread. If the intention is to update the UI, dispatch the results
    on the main thread to avoid an UIKit assertion.
 
 @note
    This method is thread safe and can be invoked from any thread (main or a background thread).
 */
- (void)executeSetPinRequest:(YKFKeyFIDO2SetPinRequest *)request completion:(YKFKeyFIDO2SessionCompletionBlock)completion;

/*!
 @method executeChangePinRequest:completion:
 
 @abstract
    Changes the existing PIN for the key FIDO2 application.
 
 @discussion
    If the key FIDO2 application doesn't have a PIN, this method will return an error and set PIN should
    be used instead. The PIN can be an alphanumeric string with the length in the range [4, 255].
 
 @param completion
    The response block which is executed after the request was processed by the key. The completion block
    will be executed on a background thread. If the intention is to update the UI, dispatch the results
    on the main thread to avoid an UIKit assertion.
 
 @note
    This method is thread safe and can be invoked from any thread (main or a background thread).
 */
- (void)executeChangePinRequest:(YKFKeyFIDO2ChangePinRequest *)request completion:(YKFKeyFIDO2SessionCompletionBlock)completion;

/*!
 @method executeGetPinRetriesWithCompletion:
 
 @abstract
    Requests the number of PIN retries from the key FIDO2 application.
 
 @param completion
    The response block which is executed after the request was processed by the key. The completion block
    will be executed on a background thread. If the intention is to update the UI, dispatch the results
    on the main thread to avoid an UIKit assertion.
 
 @note
    This method is thread safe and can be invoked from any thread (main or a background thread).
 */
- (void)executeGetPinRetriesWithCompletion:(YKFKeyFIDO2SessionGetPinRetriesCompletionBlock)completion;

/*!
 @method executeMakeCredentialRequest:completion:
 
 @abstract
    Sends to the key a FIDO2 Make Credential request to create/update a FIDO2 credential. The request
    is performed asynchronously on a background execution queue.
 
 @param completion
    The response block which is executed after the request was processed by the key. The completion block
    will be executed on a background thread. If the intention is to update the UI, dispatch the results
    on the main thread to avoid an UIKit assertion.
 
 @note
    This method is thread safe and can be invoked from any thread (main or a background thread).
 */
- (void)executeMakeCredentialRequest:(YKFKeyFIDO2MakeCredentialRequest *)request completion:(YKFKeyFIDO2SessionMakeCredentialCompletionBlock)completion;

/*!
 @method executeGetAssertionRequest:completion:
 
 @abstract
    Sends to the key a FIDO2 Get Assertion request to retrieve signatures for FIDO2 credentials. The request
    is performed asynchronously on a background execution queue.
 
 @param completion
    The response block which is executed after the request was processed by the key. The completion block
    will be executed on a background thread. If the intention is to update the UI, dispatch the results
    on the main thread to avoid an UIKit assertion.
 
 @note
    This method is thread safe and can be invoked from any thread (main or a background thread).
 */
- (void)executeGetAssertionRequest:(YKFKeyFIDO2GetAssertionRequest *)request completion:(YKFKeyFIDO2SessionGetAssertionCompletionBlock)completion;

/*!
 @method executeGetNextAssertionRequest:completion:
 
 @abstract
    Sends to the key a FIDO2 Get Next Assertion request to retrieve the next assertion from the list of
    specified FIDO2 credentials in a previous Get Assertion request. The request is performed asynchronously on
    a background execution queue.
 
 @param completion
    The response block which is executed after the request was processed by the key. The completion block
    will be executed on a background thread. If the intention is to update the UI, dispatch the results
    on the main thread to avoid an UIKit assertion.
 
 @note
    This method is thread safe and can be invoked from any thread (main or a background thread).
 */
- (void)executeGetNextAssertionWithCompletion:(YKFKeyFIDO2SessionGetAssertionCompletionBlock)completion;

/*!
 @method executeResetRequestWithCompletion:
 
 @abstract
    Sends to the key a FIDO2 Reset to revert the key FIDO2 application to factory settings.
 
 @discussion
    The reset operation is destructive. It will delete all stored credentials, including the possibility to
    compute the non-resident keys which were created with the authenticator before resetting it. To avoid an
    accidental reset during the regular operation, the reset request must be executed within 5 seconds after
    the key was powered up (plugged in) and it requires user presence (touch).
 
 @param completion
    The response block which is executed after the request was processed by the key. The completion block
    will be executed on a background thread. If the intention is to update the UI, dispatch the results
    on the main thread to avoid an UIKit assertion.
 
 @note
    This method is thread safe and can be invoked from any thread (main or a background thread).
 */
- (void)executeResetRequestWithCompletion:(YKFKeyFIDO2SessionCompletionBlock)completion;

@end

/**
 * ---------------------------------------------------------------------------------------------------------------------
 * @name YKFKeyFIDO2Service
 * ---------------------------------------------------------------------------------------------------------------------
 */

/*!
 @class YKFKeyFIDO2Service
 
 @abstract
    Provides the interface for executing FIDO2/CTAP2 requests with the key.
 @discussion
    The FIDO2 service is mantained by the key session which controls its lifecycle. The application must not
    create one. It has to use only the single shared instance from YKFAccessorySession and sync its usage with
    the session state.
 */
@interface YKFKeyFIDO2Session: NSObject<YKFKeyFIDO2SessionProtocol>

/*
 Not available: use only the shared instance from the YKFAccessorySession.
 */
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
