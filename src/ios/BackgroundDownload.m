/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements. See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership. The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License. You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied. See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "BackgroundDownload.h"
#import <objc/runtime.h>

@implementation BackgroundDownload {
    bool ignoreNextError;
}

@synthesize session;

-(DownloadHolder*) holderWithUrl:(NSString* ) downloadUri {
    if(_downloadList) {
        return [_downloadList valueForKey:downloadUri];
    }
    return nil;
}



-(DownloadHolder*) holderWithTask:(NSURLSessionTask* ) task {
    if(_downloadList) {
        @synchronized (_downloadList) {
            for (NSInteger i = 0, icount = _downloadList.count; i < icount; i ++) {
                DownloadHolder * download = _downloadList.allValues[i];
                if(download.downloadTask == task) {
                    return  download;
                }
            }
        }
  
    }
    return nil;
}

- (void)startAsync:(CDVInvokedUrlCommand*)command
{
    
    if(!_downloadList) {
        _downloadList = [[NSMutableDictionary alloc] init];
    }
    
    NSString * downloadUri = [command.arguments objectAtIndex:0];
    DownloadHolder * task = [self holderWithUrl:downloadUri];
    if(!task) {
        task = [[DownloadHolder alloc] init];
        task.downloadUri = downloadUri;
        task.targetFile = [command.arguments objectAtIndex:1];
        task.callbackId = command.callbackId;

    	NSURL *url = [NSURL URLWithString: [[task.downloadUri stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding]
                                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        session = [self backgroundSession];
        task.downloadTask = [session downloadTaskWithRequest:request];
        @synchronized (_downloadList){
            [_downloadList setValue:task forKey:task.downloadUri];
        }
        [task.downloadTask resume];
    }
    else {
        [task.downloadTask resume];
    }
    
    ignoreNextError = NO;
    [session getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
                if (downloadTasks.count > 0) {
                    for (NSInteger i = 0, icount = downloadTasks.count; i < icount; i ++) {
                        [downloadTasks[i] resume];
                    }
                }
    }];
}

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
- (NSURLSession *)backgroundSession
{
    static NSURLSession *backgroundSession = nil;
    static dispatch_once_t onceToken;
    
    NSURLSessionConfiguration *config;
    BOOL iOS8OrNewer = [[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0;
    if (iOS8OrNewer) {
        config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"com.cordova.plugin.BackgroundDownload.BackgroundSession"];
    } else {
        config = [NSURLSessionConfiguration backgroundSessionConfiguration:@"com.cordova.plugin.BackgroundDownload.BackgroundSession"];
    }
    
    dispatch_once(&onceToken, ^{
        backgroundSession = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    });
    return backgroundSession;
}
#pragma GCC diagnostic pop

- (void)stop:(CDVInvokedUrlCommand*)command
{
    CDVPluginResult* pluginResult = nil;
    NSString* myarg = [command.arguments objectAtIndex:0];
    
    if (myarg != nil) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Arg was null"];
    }
    
    DownloadHolder * holder = [self holderWithUrl:myarg];
    if(holder){
        if(holder.downloadTask.state == NSURLSessionTaskStateCompleted) {
            @synchronized (_downloadList){
                [_downloadList removeObjectForKey: holder.downloadUri];
            }
        }
        else {
            [holder.downloadTask cancel];
        }
       
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    DownloadHolder * holder = [self holderWithTask:downloadTask];
    if(holder == nil) return;
    NSMutableDictionary* progressObj = [NSMutableDictionary dictionaryWithCapacity:1];
    [progressObj setObject:[NSNumber numberWithInteger:totalBytesWritten] forKey:@"bytesReceived"];
    [progressObj setObject:[NSNumber numberWithInteger:totalBytesExpectedToWrite] forKey:@"totalBytesToReceive"];
    NSMutableDictionary* resObj = [NSMutableDictionary dictionaryWithCapacity:1];
    [resObj setObject:progressObj forKey:@"progress"];
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:resObj];
    result.keepCallback = [NSNumber numberWithInteger: TRUE];
    [self.commandDelegate sendPluginResult:result callbackId: holder.callbackId];
}

-(void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    
    if (ignoreNextError) {
        ignoreNextError = NO;
        return;
    }
    DownloadHolder * holder = [self holderWithTask:task];
    if(holder == nil) return;
    NSLog(@"didCompleteWithError %@", holder.downloadUri);
    if (error != nil) {
        if ((error.code == -999)) {
            NSData* resumeData = [[error userInfo] objectForKey:NSURLSessionDownloadTaskResumeData];
            // resumeData is available only if operation was terminated by the system (no connection or other reason)
            // this happens when application is closed when there is pending download, so we try to resume it
            if (resumeData != nil) {
                ignoreNextError = YES;
                return;
            }
        }
        CDVPluginResult* errorResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
        [self.commandDelegate sendPluginResult:errorResult callbackId: holder.callbackId];
    } else if ([[task response] isKindOfClass:[NSHTTPURLResponse class]]) {
		NSInteger statusCode = [(NSHTTPURLResponse *)[task response] statusCode];

		if (statusCode != 200) {
		  NSDictionary* dictionary = @{@"statusCode": [NSNumber numberWithInt:statusCode]};
		  CDVPluginResult* errorResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
		  [self.commandDelegate sendPluginResult:errorResult callbackId:self.callbackId];
		} else {
		  CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
		  [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
		}
	} else {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId: holder.callbackId];
    }
    @synchronized (_downloadList) {
        [_downloadList removeObjectForKey:holder.downloadUri];
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    DownloadHolder * holder = [self holderWithTask:downloadTask];
    if(holder){
        NSLog(@"didFinishDownloadingToURL %@", holder.downloadUri);
        NSFileManager *fileManager = [NSFileManager defaultManager];
    
        NSURL *targetURL = [NSURL URLWithString:holder.targetFile];
    
        [fileManager removeItemAtPath:targetURL.path error: nil];
        [fileManager createFileAtPath:targetURL.path contents:[fileManager contentsAtPath:[location path]] attributes:nil];
    }
}
@end

@implementation DownloadHolder

@end
