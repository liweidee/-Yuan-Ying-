#import <Foundation/Foundation.h>

@interface NodeJSManager : NSObject

@property (nonatomic, assign, readonly) BOOL isRunning;
@property (nonatomic, assign, readonly) BOOL isNodeReady;
@property (nonatomic, assign, readonly) int nativeServerPort;
@property (nonatomic, assign, readonly) int managementPort;
@property (nonatomic, assign, readonly) int spiderPort;

+ (instancetype)shared;

- (void)startNodeJS:(void (^)(BOOL))completion;
- (void)stopNodeJS;
- (int)getNativeServerPort;
- (int)getManagementPort;
- (int)getSpiderPort;

- (void)loadSourceFromURL:(NSString *)urlString
               completion:(void (^)(BOOL success, NSString * _Nullable message))completion;

- (void)deleteSourceWithCompletion:(void (^)(BOOL success))completion;

- (NSString *)getDocumentsSourcePath;

/// 启动 NodeJS 保活（通过 SilenceKeeper 维持音频会话）
- (void)startKeepAlive;

/// 停止 NodeJS 保活
- (void)stopKeepAlive;

@end
