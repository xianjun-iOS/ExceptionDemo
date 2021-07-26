//
//  XJUncaughtExceptionHandler.m
//  ExceptionDemo
//
//  Created by Baypac on 2021/7/26.
//

#import "XJUncaughtExceptionHandler.h"
#import <UIKit/UIKit.h>

#include <libkern/OSAtomic.h>
#include <execinfo.h>
#include <stdatomic.h>

// 异常名称key
NSString * const XJUncaughtExceptionHandlerSignalExceptionName = @"XJUncaughtExceptionHandlerSignalExceptionName";
// 异常原因key
NSString * const XJUncaughtExceptionHandlerSignalExceptionReason = @"XJUncaughtExceptionHandlerSignalExceptionReason";
// 精简的函数调用栈key
NSString * const XJUncaughtExceptionHandlerAddressesKey = @"XJUncaughtExceptionHandlerAddressesKey";
// 异常文件key
NSString * const XJUncaughtExceptionHandlerFileKey = @"XJUncaughtExceptionHandlerFileKey";
// 异常符号key
NSString * const XJUncaughtExceptionHandlerCallStackSymbolsKey = @"XJUncaughtExceptionHandlerCallStackSymbolsKey";
// signal异常key
NSString * const XJUncaughtExceptionHandlerSignalKey = @"XJUncaughtExceptionHandlerSignalKey";


atomic_int      XJUncaughtExceptionCount = 0;
const int32_t   XJUncaughtExceptionMaximum = 8;
const NSInteger XJUncaughtExceptionHandlerSkipAddressCount = 4;
const NSInteger XJUncaughtExceptionHandlerReportAddressCount = 5;

// 保存原先的exception handler
NSUncaughtExceptionHandler *originalUncaughtExceptionHandler = NULL;

// 保存原先的abrt handler
void (*originalAbrtSignalHandler)(int, struct __siginfo *, void *);

@implementation XJUncaughtExceptionHandler

/// exception回调，由_objc_terminate调用
void XJExceptionHandlers(NSException *exception) {
    NSLog(@"%s",__func__);
    
    int32_t exceptionCount = atomic_fetch_add_explicit(&XJUncaughtExceptionCount,1,memory_order_relaxed);
    if (exceptionCount > XJUncaughtExceptionMaximum) {
        return;
    }
    // 获取堆栈信息
    NSArray *callStack = [XJUncaughtExceptionHandler xj_backtrace];
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:[exception userInfo]];
    [userInfo setObject:exception.name forKey:XJUncaughtExceptionHandlerSignalExceptionName];
    [userInfo setObject:exception.reason forKey:XJUncaughtExceptionHandlerSignalExceptionReason];
    [userInfo setObject:callStack forKey:XJUncaughtExceptionHandlerAddressesKey];
    [userInfo setObject:exception.callStackSymbols forKey:XJUncaughtExceptionHandlerCallStackSymbolsKey];
    [userInfo setObject:@"XJException" forKey:XJUncaughtExceptionHandlerFileKey];
    
    [[[XJUncaughtExceptionHandler alloc] init]
     performSelectorOnMainThread:@selector(xj_handleException:)
     withObject:
     [NSException
      exceptionWithName:[exception name]
      reason:[exception reason]
      userInfo:userInfo]
     waitUntilDone:YES];
    
    // 自定义处理完成之后，调用原先的
    if (originalUncaughtExceptionHandler) {
        originalUncaughtExceptionHandler(exception);
    }
    
}

// signal处理
void XJSignalHandler(int signal) {
    NSLog(@"%s",__func__);
    
    int32_t exceptionCount = atomic_fetch_add_explicit(&XJUncaughtExceptionCount,1,memory_order_relaxed);
    if (exceptionCount > XJUncaughtExceptionMaximum) {
        return;
    }
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:[NSNumber numberWithInt:signal] forKey:XJUncaughtExceptionHandlerSignalKey];
        NSArray *callStack = [XJUncaughtExceptionHandler xj_backtrace];
        [userInfo setObject:callStack forKey:XJUncaughtExceptionHandlerAddressesKey];
        [userInfo setObject:@"XJSignalCrash" forKey:XJUncaughtExceptionHandlerFileKey];
        [userInfo setObject:callStack forKey:XJUncaughtExceptionHandlerCallStackSymbolsKey];

        [[[XJUncaughtExceptionHandler alloc] init]
         performSelectorOnMainThread:@selector(xj_handleException:) withObject:
         [NSException
          exceptionWithName:XJUncaughtExceptionHandlerSignalExceptionName
          reason:[NSString stringWithFormat:NSLocalizedString(@"Signal %d was raised.\n %@", nil),signal, getAppInfo()]
          userInfo:userInfo]
         waitUntilDone:YES];
}

static void XJAbrtSignalHandler(int signal, siginfo_t *info, void *context) {
    XJSignalHandler(signal);
    
    // 自定义处理完成之后，调用原先的
    if (signal == SIGABRT && originalAbrtSignalHandler) {
        originalAbrtSignalHandler(signal, info, context);
    }
}

+ (void)installUncaughtSignalExceptionHandler {
    // 可以通过 NSGetUncaughtExceptionHandler 先保存旧的，然后赋值自己新的。
    if (NSGetUncaughtExceptionHandler() != XJExceptionHandlers) {
        originalUncaughtExceptionHandler = NSGetUncaughtExceptionHandler();
    }
    
    //XJExceptionHandlers 赋值给 uncaught_handler()，最终_objc_terminate 调用 XJExceptionHandlers
    //NSSetUncaughtExceptionHandler 是 objc_setUncaughtExceptionHandler()的上层实现
    NSSetUncaughtExceptionHandler(&XJExceptionHandlers);
    
    // 信号量截断
//    [self registerSignalHandler];
    [self registerSigactionHandler];
}

// 方式一：通过 signal 注册
+ (void)registerSignalHandler {
    signal(SIGHUP, XJSignalHandler);
    signal(SIGINT, XJSignalHandler);
    signal(SIGQUIT, XJSignalHandler);
    signal(SIGABRT, XJSignalHandler);
    signal(SIGILL, XJSignalHandler);
    signal(SIGSEGV, XJSignalHandler);
    signal(SIGFPE, XJSignalHandler);
    signal(SIGBUS, XJSignalHandler);
    signal(SIGPIPE, XJSignalHandler);
}

// 方式二：通过 sigaction 注册
+ (void)registerSigactionHandler {
    struct sigaction old_action;
    sigaction(SIGABRT, NULL, &old_action);
    if (old_action.sa_flags & SA_SIGINFO) {
        if (old_action.sa_sigaction != XJAbrtSignalHandler) {
            //保存之前注册的handler
            originalAbrtSignalHandler = old_action.sa_sigaction;
        }
    }

    struct sigaction action;
    action.sa_sigaction = XJAbrtSignalHandler;
    action.sa_flags = SA_NODEFER | SA_SIGINFO;
    sigemptyset(&action.sa_mask);
    sigaction(SIGABRT, &action, 0);
}

+ (void)removeRegister:(NSException *)exception {
    // exception
    NSSetUncaughtExceptionHandler(NULL);
    
    // signal
    signal(SIGHUP, SIG_DFL);
    signal(SIGINT, SIG_DFL);
    signal(SIGQUIT, SIG_DFL);
    signal(SIGABRT, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGSEGV, SIG_DFL);
    signal(SIGFPE, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    
    NSLog(@"%@",[exception name]);
    
    //signal
    if ([[exception name] isEqual:XJUncaughtExceptionHandlerSignalExceptionName]) {
        kill(getpid(), [[[exception userInfo] objectForKey:XJUncaughtExceptionHandlerSignalKey] intValue]);
    } else {
    //exception
        [exception raise];
    }
}

- (void)xj_handleException:(NSException *)exception{
    // 保存奔溃信息或者上传
    
    NSDictionary *userinfo = [exception userInfo];
    [self saveCrash:exception file:[userinfo objectForKey:XJUncaughtExceptionHandlerFileKey]];
    
    // UI提示相关操作
    // 如果要做 UI 相关提示需要写runloop相关的代码
    
    // 移除注册
    [XJUncaughtExceptionHandler removeRegister:exception];
}

/// 保存奔溃信息或者上传
- (void)saveCrash:(NSException *)exception file:(NSString *)file{
    
    NSArray *stackArray = [[exception userInfo] objectForKey:XJUncaughtExceptionHandlerCallStackSymbolsKey];// 异常的堆栈信息
    NSString *reason = [exception reason];// 出现异常的原因
    NSString *name = [exception name];// 异常名称
    
    // 可以直接用代码，输入这个崩溃信息，以便在console中进一步分析错误原因
    // NSLog(@"crash: %@", exception);
    
    NSString * _libPath  = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:file];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:_libPath]){
        [[NSFileManager defaultManager] createDirectoryAtPath:_libPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSDate *date = [NSDate dateWithTimeIntervalSinceNow:0];
    NSTimeInterval interval = [date timeIntervalSince1970];
    NSString *timeString = [NSString stringWithFormat:@"%f", interval];
    
    NSString * savePath = [_libPath stringByAppendingFormat:@"/error%@.log",timeString];
    
    NSString *exceptionInfo = [NSString stringWithFormat:@"Exception reason：%@\nException name：%@\nException stack：%@",name, reason, stackArray];
    
    BOOL sucess = [exceptionInfo writeToFile:savePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    NSLog(@"save crash log sucess:%d, path:%@",sucess,savePath);
    
    // 保存之后可以做上传相关操作
    
}

/// 获取函数堆栈信息
+ (NSArray *)xj_backtrace{
    
    void* callstack[128];
    int frames = backtrace(callstack, 128);//用于获取当前线程的函数调用堆栈，返回实际获取的指针个数
    char **strs = backtrace_symbols(callstack, frames);//从backtrace函数获取的信息转化为一个字符串数组
    int i;
    NSMutableArray *backtrace = [NSMutableArray arrayWithCapacity:frames];
    for (i = XJUncaughtExceptionHandlerSkipAddressCount;
         i < XJUncaughtExceptionHandlerSkipAddressCount+XJUncaughtExceptionHandlerReportAddressCount;
         i++)
    {
        [backtrace addObject:[NSString stringWithUTF8String:strs[i]]];
    }
    free(strs);
    return backtrace;
}

//获取应用信息
NSString *getAppInfo() {
    NSString *appInfo = [NSString stringWithFormat:@"App : %@ %@(%@)\nDevice : %@\nOS Version : %@ %@\n",
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"],
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
                         [UIDevice currentDevice].model,
                         [UIDevice currentDevice].systemName,
                         [UIDevice currentDevice].systemVersion];
    NSLog(@"Crash!!!! %@", appInfo);
    return appInfo;
}

@end
