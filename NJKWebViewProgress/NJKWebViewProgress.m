//
//  NJKWebViewProgress.m
//
//  Created by Satoshi Aasano on 4/20/13.
//  Copyright (c) 2013 Satoshi Asano. All rights reserved.
//

#import "NJKWebViewProgress.h"

NSString *completeRPCURL = @"webviewprogressproxy:///complete";

static const float initialProgressValue = 0.1;
static const float beforeInteractiveMaxProgressValue = 0.5;
static const float afterInteractiveMaxProgressValue = 0.9;

@implementation NJKWebViewProgress
{
    NSUInteger _loadingCount;
    NSUInteger _maxLoadCount;
    NSURL *_currentURL;
    BOOL _interactive;
}

- (id)init
{
    self = [super init];
    if (self) {
        _maxLoadCount = _loadingCount = 0;
        _interactive = NO;
    }
    return self;
}

- (void)startProgress
{
    if (_progress < initialProgressValue) {
        [self setProgress:initialProgressValue];
    }
}

- (void)incrementProgress
{
    float progress = self.progress;
    float maxProgress = _interactive ? afterInteractiveMaxProgressValue : beforeInteractiveMaxProgressValue;
    float remainPercent = (float)_loadingCount / (float)_maxLoadCount;
    float increment = (maxProgress - progress) * remainPercent;
    progress += increment;
    progress = fmin(progress, maxProgress);
    [self setProgress:progress];
}

- (void)completeProgress
{
    [self setProgress:1.0];
}

- (void)setProgress:(float)progress
{
    id<NJKWebViewProgressDelegate> progressDelegate = _progressDelegate;
    // progress should be incremental only
    if (progress > _progress || progress == 0) {
        _progress = progress;
        if ([progressDelegate respondsToSelector:@selector(webViewProgress:updateProgress:)]) {
            [progressDelegate webViewProgress:self updateProgress:progress];
        }
        if (_progressBlock) {
            _progressBlock(progress);
        }
    }
}

- (void)reset
{
    _maxLoadCount = _loadingCount = 0;
    _interactive = NO;
    [self setProgress:0.0];
}

#pragma mark -
#pragma mark UIWebViewDelegate

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    BOOL ret = YES;
    id<UIWebViewDelegate> webViewProxyDelegate = _webViewProxyDelegate;
    if ([webViewProxyDelegate respondsToSelector:@selector(webView:shouldStartLoadWithRequest:navigationType:)]) {
        ret = [webViewProxyDelegate webView:webView shouldStartLoadWithRequest:request navigationType:navigationType];
    }
    
    if ([request.URL.absoluteString isEqualToString:completeRPCURL]) {
        [self completeProgress];
        return NO;
    }
    
    BOOL isFragmentJump = NO;
    if (request.URL.fragment) {
        NSString *nonFragmentURL = [request.URL.absoluteString stringByReplacingOccurrencesOfString:[@"#" stringByAppendingString:request.URL.fragment] withString:@""];
        isFragmentJump = [nonFragmentURL isEqualToString:webView.request.URL.absoluteString];
    }

    BOOL isTopLevelNavigation = [request.mainDocumentURL isEqual:request.URL];

    BOOL isHTTP = [request.URL.scheme isEqualToString:@"http"] || [request.URL.scheme isEqualToString:@"https"];
    if (ret && !isFragmentJump && isHTTP && isTopLevelNavigation) {
        _currentURL = request.URL;
        [self reset];
    }
    return ret;
}

- (void)webViewDidStartLoad:(UIWebView *)webView
{
    id<UIWebViewDelegate> webViewProxyDelegate = _webViewProxyDelegate;
    if ([webViewProxyDelegate respondsToSelector:@selector(webViewDidStartLoad:)]) {
        [webViewProxyDelegate webViewDidStartLoad:webView];
    }

    _loadingCount++;
    _maxLoadCount = fmax(_maxLoadCount, _loadingCount);

    [self startProgress];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    id<UIWebViewDelegate> webViewProxyDelegate = _webViewProxyDelegate;
    if ([webViewProxyDelegate respondsToSelector:@selector(webViewDidFinishLoad:)]) {
        [webViewProxyDelegate webViewDidFinishLoad:webView];
    }
    
    _loadingCount--;
    [self incrementProgress];
    
    NSString *readyState = [webView stringByEvaluatingJavaScriptFromString:@"document.readyState"];

    BOOL interactive = [readyState isEqualToString:@"interactive"];
    if (interactive) {
        _interactive = YES;
        NSString *waitForCompleteJS = [NSString stringWithFormat:@"window.addEventListener('load',function() { var iframe = document.createElement('iframe'); iframe.style.display = 'none'; iframe.src = '%@'; document.body.appendChild(iframe);  }, false);", completeRPCURL];
        [webView stringByEvaluatingJavaScriptFromString:waitForCompleteJS];
    }
    
    BOOL isNotRedirect = _currentURL && [_currentURL isEqual:webView.request.mainDocumentURL];
    BOOL complete = [readyState isEqualToString:@"complete"];
    if (complete && isNotRedirect) {
        [self completeProgress];
    }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    id<UIWebViewDelegate> webViewProxyDelegate = _webViewProxyDelegate;
    if ([webViewProxyDelegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) {
        [webViewProxyDelegate webView:webView didFailLoadWithError:error];
    }
    
    _loadingCount--;
    [self incrementProgress];

    NSString *readyState = [webView stringByEvaluatingJavaScriptFromString:@"document.readyState"];

    BOOL interactive = [readyState isEqualToString:@"interactive"];
    if (interactive) {
        _interactive = YES;
        NSString *waitForCompleteJS = [NSString stringWithFormat:@"window.addEventListener('load',function() { var iframe = document.createElement('iframe'); iframe.style.display = 'none'; iframe.src = '%@'; document.body.appendChild(iframe);  }, false);", completeRPCURL];
        [webView stringByEvaluatingJavaScriptFromString:waitForCompleteJS];
    }
    
    BOOL isNotRedirect = _currentURL && [_currentURL isEqual:webView.request.mainDocumentURL];
    BOOL complete = [readyState isEqualToString:@"complete"];
    if (complete && isNotRedirect) {
        [self completeProgress];
    }
}

#pragma mark - 
#pragma mark Method Forwarding
// for future UIWebViewDelegate impl

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
    NSMethodSignature *signature = [super methodSignatureForSelector:selector];
    id<UIWebViewDelegate> webViewProxyDelegate = _webViewProxyDelegate;
    if(!signature) {
        if([webViewProxyDelegate respondsToSelector:selector]) {
            return [(NSObject *)webViewProxyDelegate methodSignatureForSelector:selector];
        }
    }
    return signature;
}

- (void)forwardInvocation:(NSInvocation*)invocation
{
    id<UIWebViewDelegate> webViewProxyDelegate = _webViewProxyDelegate;
    if ([webViewProxyDelegate respondsToSelector:[invocation selector]]) {
        [invocation invokeWithTarget:webViewProxyDelegate];
    }
}

@end
