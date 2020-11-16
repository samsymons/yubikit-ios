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

#import "YKFKeySession.h"
#import "YKFAccessoryConnectionController.h"
#import "YKFNSDataAdditions.h"
#import "YKFNSDataAdditions+Private.h"
#import "YKFKeyAPDUError.h"
#import "YKFAssert.h"

@implementation YKFKeySession

#pragma mark - Key Response

+ (NSData *)dataFromKeyResponse:(NSData *)response {
    YKFParameterAssertReturnValue(response, [NSData data]);
    YKFAssertReturnValue(response.length >= 2, @"Key response data is too short.", [NSData data]);
    
    if (response.length == 2) {
        return [NSData data];
    } else {
        NSRange range = {0, response.length - 2};
        return [response subdataWithRange:range];
    }
}

#pragma mark - Status Code

+ (UInt16)statusCodeFromKeyResponse:(NSData *)response {
    YKFParameterAssertReturnValue(response, YKFKeyAPDUErrorCodeWrongLength);
    YKFAssertReturnValue(response.length >= 2, @"Key response data is too short.", YKFKeyAPDUErrorCodeWrongLength);
    
    return [response ykf_getBigEndianIntegerInRange:NSMakeRange([response length] - 2, 2)];
}

@end
