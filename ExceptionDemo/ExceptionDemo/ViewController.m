//
//  ViewController.m
//  ExceptionDemo
//
//  Created by Baypac on 2021/7/26.
//

#import "ViewController.h"

@interface ViewController ()

@property (nonatomic, strong) NSArray *dataList;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.dataList = @[@"0",@"1",@"2",@"3",@"4"];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
//    //exception错误
//    NSLog(@"%@",self.dataList[5]);
        
    //signal 错误
    void *singal = malloc(1024);
    free(singal);
    free(singal);//SIGABRT的错误
}

@end
