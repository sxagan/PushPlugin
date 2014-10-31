/*
 Copyright 2009-2011 Urban Airship Inc. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binaryform must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided withthe distribution.

 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "PushPlugin.h"

@implementation PushPlugin

@synthesize notificationMessage;
@synthesize isInline;

@synthesize callbackId;
@synthesize notificationCallbackId;
@synthesize callback;


- (void)unregister:(CDVInvokedUrlCommand*)command {
    self.callbackId = command.callbackId;

    [[UIApplication sharedApplication] unregisterForRemoteNotifications];

    [self successWithMessage:@"unregistered"];
}

- (void)register:(CDVInvokedUrlCommand*)command {
    self.callbackId = command.callbackId;

    NSMutableDictionary* options = [command.arguments objectAtIndex:0];

    id badgeArg = [options objectForKey:@"badge"];
    id soundArg = [options objectForKey:@"sound"];
    id alertArg = [options objectForKey:@"alert"];

    BOOL badgeEnabled = NO;
    BOOL soundEnabled = NO;
    BOOL alertEnabled = NO;

    if ([badgeArg isKindOfClass:[NSString class]])
    {
        if ([badgeArg isEqualToString:@"true"])
            badgeEnabled = YES;
    }
    else if ([badgeArg boolValue])
        badgeEnabled = YES;

    if ([soundArg isKindOfClass:[NSString class]])
    {
        if ([soundArg isEqualToString:@"true"])
            soundEnabled = YES;
    }
    else if ([soundArg boolValue])
        soundEnabled = YES;

    if ([alertArg isKindOfClass:[NSString class]])
    {
        if ([alertArg isEqualToString:@"true"])
            alertEnabled = YES;
    }
    else if ([alertArg boolValue])
        alertEnabled = YES;

    self.callback = [options objectForKey:@"ecb"];


    isInline = NO;

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
    if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        // iOS8 in iOS8 SDK
        [self enableiOS8NotificationsWithBadgeEnabled:badgeEnabled SoundEnabled:soundEnabled AlertEnabled:alertEnabled];
    } else {
        // iOS7 in iOS8 SDK
        [self enableiOS7NotificationsWithBadgeEnabled:badgeEnabled SoundEnabled:soundEnabled AlertEnabled:alertEnabled];
    }
#else
    // iOS7 in iOS7 SDK
    [self enableiOS7NotificationsWithBadgeEnabled:badgeEnabled SoundEnabled:soundEnabled AlertEnabled:alertEnabled];
#endif

    if (notificationMessage)            // if there is a pending startup notification
        [self notificationReceived];    // go ahead and process it
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
- (void) enableiOS8NotificationsWithBadgeEnabled:(BOOL) badgeEnabled SoundEnabled:(BOOL) soundEnabled AlertEnabled:(BOOL) alertEnabled {
    UIUserNotificationType notificationTypes = UIUserNotificationTypeNone;

    if (badgeEnabled)
        notificationTypes |= UIUserNotificationTypeBadge;

    if (soundEnabled)
        notificationTypes |= UIUserNotificationTypeSound;

    if (alertEnabled)
        notificationTypes |= UIUserNotificationTypeAlert;

    if (notificationTypes == UIUserNotificationTypeNone)
        NSLog(@"PushPlugin.register: Push notification type is set to none");

    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:notificationTypes categories:nil];

    [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
}
#endif

- (void) enableiOS7NotificationsWithBadgeEnabled:(BOOL) badgeEnabled SoundEnabled:(BOOL) soundEnabled AlertEnabled:(BOOL) alertEnabled {
    UIRemoteNotificationType notificationTypes = UIRemoteNotificationTypeNone;
    if (badgeEnabled)
        notificationTypes |= UIRemoteNotificationTypeBadge;

    if (soundEnabled)
        notificationTypes |= UIRemoteNotificationTypeSound;

    if (alertEnabled)
        notificationTypes |= UIRemoteNotificationTypeAlert;

    if (notificationTypes == UIRemoteNotificationTypeNone)
        NSLog(@"PushPlugin.register: Push notification type is set to none");

    [[UIApplication sharedApplication] registerForRemoteNotificationTypes:notificationTypes];
}

-(void) didRegisterUserNotificationSettings:(UIUserNotificationSettings *)settings {
    if ([settings types] != UIUserNotificationTypeNone) {
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    } else {
        [self failWithMessage:@"User denied displaying of notifications" withError:nil];
    }
}

- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {

    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    NSString *token = [[[[deviceToken description] stringByReplacingOccurrencesOfString:@"<"withString:@""]
                        stringByReplacingOccurrencesOfString:@">" withString:@""]
                       stringByReplacingOccurrencesOfString: @" " withString: @""];
    [results setValue:token forKey:@"deviceToken"];

#if !TARGET_IPHONE_SIMULATOR
    // Get Bundle Info for Remote Registration (handy if you have more than one app)
    [results setValue:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"] forKey:@"appName"];
    [results setValue:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] forKey:@"appVersion"];

    // Set the defaults to disabled unless we find otherwise...
    NSString *pushBadge = @"disabled";
    NSString *pushAlert = @"disabled";
    NSString *pushSound = @"disabled";

    // Check what Notifications the user has turned on.  We registered for all three, but they may have manually disabled some or all of them.
    // Also Check what Registered Types are turned on. This is a bit tricky since if two are enabled, and one is off, it will return a number 2... not telling you which
    // one is actually disabled. So we are literally checking to see if rnTypes matches what is turned on, instead of by number. The "tricky" part is that the
    // single notification types will only match if they are the ONLY one enabled.  Likewise, when we are checking for a pair of notifications, it will only be
    // true if those two notifications are on.  This is why the code is written this way
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
    if ([[UIApplication sharedApplication] isRegisteredForRemoteNotifications]) {
        UIUserNotificationType rntypes = [[[UIApplication sharedApplication] currentUserNotificationSettings] types];

        if(rntypes & UIUserNotificationTypeBadge) {
            pushBadge = @"enabled";
        }
        if(rntypes & UIUserNotificationTypeAlert) {
            pushAlert = @"enabled";
        }
        if(rntypes & UIUserNotificationTypeSound) {
            pushSound = @"enabled";
        }
    }
#else
    UIRemoteNotificationType rntypes = [[UIApplication sharedApplication] enabledRemoteNotificationTypes];

    if(rntypes & UIRemoteNotificationTypeBadge) {
        pushBadge = @"enabled";
    }
    if(rntypes & UIRemoteNotificationTypeAlert) {
        pushAlert = @"enabled";
    }
    if(rntypes & UIRemoteNotificationTypeSound) {
        pushSound = @"enabled";
    }
#endif

    [results setValue:pushBadge forKey:@"pushBadge"];
    [results setValue:pushAlert forKey:@"pushAlert"];
    [results setValue:pushSound forKey:@"pushSound"];

    // Get the users Device Model, Display Name, Token & Version Number
    UIDevice *dev = [UIDevice currentDevice];
    [results setValue:dev.name forKey:@"deviceName"];
    [results setValue:dev.model forKey:@"deviceModel"];
    [results setValue:dev.systemVersion forKey:@"deviceSystemVersion"];

    [self successWithMessage:[NSString stringWithFormat:@"%@", token]];
#endif
}

- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    [self failWithMessage:[error description] withError:error];
}

- (void)notificationReceived {
    NSLog(@"Notification received");

    if (notificationMessage && self.callback) {
        NSMutableString *jsonStr = [NSMutableString stringWithString:@"{"];

        [self parseDictionary:notificationMessage intoJSON:jsonStr];

        if (isInline) {
            [jsonStr appendFormat:@"foreground:\"%d\"", 1];
            isInline = NO;
        } else {
            [jsonStr appendFormat:@"foreground:\"%d\"", 0];
        }

        [jsonStr appendString:@"}"];

        NSLog(@"Msg: %@", jsonStr);

        NSString * jsCallBack = [NSString stringWithFormat:@"setTimeout(function(){%@(%@)}, 0);", self.callback, jsonStr];
        [self.webView stringByEvaluatingJavaScriptFromString:jsCallBack];

        self.notificationMessage = nil;
    }
}

// reentrant method to drill down and surface all sub-dictionaries' key/value pairs into the top level json
-(void)parseDictionary:(NSDictionary *)inDictionary intoJSON:(NSMutableString *)jsonString {
    NSArray         *keys = [inDictionary allKeys];
    NSString        *key;

    for (key in keys) {
        id thisObject = [inDictionary objectForKey:key];

        if ([thisObject isKindOfClass:[NSDictionary class]])
            [self parseDictionary:thisObject intoJSON:jsonString];
        else
            [jsonString appendFormat:@"%@:\"%@\",", key, [inDictionary objectForKey:key]];
    }
}

- (void)setApplicationIconBadgeNumber:(CDVInvokedUrlCommand *)command {

    self.callbackId = command.callbackId;

    NSMutableDictionary* options = [command.arguments objectAtIndex:0];
    int badge = [[options objectForKey:@"badge"] intValue] ?: 0;

    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:badge];

    [self successWithMessage:[NSString stringWithFormat:@"app badge count set to %d", badge]];
}

-(void)successWithMessage:(NSString *)message {
    CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:message];

    [self.commandDelegate sendPluginResult:commandResult callbackId:self.callbackId];
}

-(void)failWithMessage:(NSString *)message withError:(NSError *)error {
    NSString *errorMessage = (error) ? [NSString stringWithFormat:@"%@ - %@", message, [error localizedDescription]] : message;
    CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];

    [self.commandDelegate sendPluginResult:commandResult callbackId:self.callbackId];
}

@end
