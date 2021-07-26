//
//  XJUncaughtExceptionHandler.h
//  ExceptionDemo
//
//  Created by Baypac on 2021/7/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XJUncaughtExceptionHandler : NSObject

+ (void)installUncaughtSignalExceptionHandler;

@end

NS_ASSUME_NONNULL_END
