// 1) Google Maps：導航說話時不壓低音樂（移除 DuckOthers）
// 2) 神盾測速照相：播放語音時自動放大音量（預錄音檔走 AVAudioPlayer 時有效）
#import <AVFoundation/AVFoundation.h>
#import <math.h>

// ====== 想調整神盾的放大幅度，只要改這個數字（單位 dB）======
// 6 = 約 2 倍振幅，12 = 約 4 倍，18 = 約 8 倍。破音就調小。
static const float kShieldGainDB = 12.0f;

// ---------- Google Maps ----------
static AVAudioSessionCategoryOptions fixOptions(NSString *cat, AVAudioSessionCategoryOptions o) {
    if (!(o & AVAudioSessionCategoryOptionDuckOthers)) return o;
    o &= ~AVAudioSessionCategoryOptionDuckOthers;
    if ([cat isEqualToString:AVAudioSessionCategoryPlayback] ||
        [cat isEqualToString:AVAudioSessionCategoryPlayAndRecord] ||
        [cat isEqualToString:AVAudioSessionCategoryMultiRoute]) {
        o |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    NSLog(@"[GoogleMapsNoDuck] removed DuckOthers, category=%@ options=%lu", cat, (unsigned long)o);
    return o;
}

%group MapsFix
%hook AVAudioSession
- (BOOL)setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    return %orig(category, fixOptions(category, options), outError);
}
- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    return %orig(category, mode, fixOptions(category, options), outError);
}
- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode routeSharingPolicy:(AVAudioSessionRouteSharingPolicy)policy options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    return %orig(category, mode, policy, fixOptions(category, options), outError);
}
%end
%end

// ---------- 神盾：放大語音 ----------
static NSURL *boostedURL(NSURL *url) {
    @try {
        if (!url || !url.isFileURL) return url;
        if ([url.path containsString:@"/ShieldBoost/"]) return url; // 已經處理過
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ShieldBoost"];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *base = [url.lastPathComponent stringByDeletingPathExtension];
        NSString *name = [NSString stringWithFormat:@"%lx_%@_%d.caf", (unsigned long)url.path.hash, base, (int)kShieldGainDB];
        NSURL *out = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]];
        if ([fm fileExistsAtPath:out.path]) return out;

        NSError *err = nil;
        AVAudioFile *in = [[AVAudioFile alloc] initForReading:url error:&err];
        if (!in) return url;
        AVAudioFormat *fmt = in.processingFormat;
        AVAudioFramePosition len = in.length;
        if (len <= 0 || len > (AVAudioFramePosition)(fmt.sampleRate * 60)) return url; // 太長就不處理
        AVAudioPCMBuffer *buf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fmt frameCapacity:(AVAudioFrameCount)len];
        if (!buf || ![in readIntoBuffer:buf error:&err]) return url;

        float g = powf(10.0f, kShieldGainDB / 20.0f);
        for (AVAudioChannelCount c = 0; c < fmt.channelCount; c++) {
            float *p = buf.floatChannelData[c];
            for (AVAudioFrameCount i = 0; i < buf.frameLength; i++) {
                float v = p[i] * g, a = fabsf(v);
                if (a > 0.8f) { a = 0.8f + 0.2f * tanhf((a - 0.8f) / 0.2f); v = (v < 0 ? -a : a); } // 軟限幅，避免爆音
                p[i] = v;
            }
        }
        AVAudioFile *outFile = [[AVAudioFile alloc] initForWriting:out settings:fmt.settings error:&err];
        if (!outFile || ![outFile writeFromBuffer:buf error:&err]) { [fm removeItemAtURL:out error:nil]; return url; }
        outFile = nil;
        NSLog(@"[ShieldBoost] boosted %@ by %.0f dB", url.lastPathComponent, kShieldGainDB);
        return out;
    } @catch (__unused NSException *e) {
        return url;
    }
}

%group ShieldBoost
%hook AVAudioPlayer
- (id)initWithContentsOfURL:(NSURL *)url error:(NSError **)outError {
    return %orig(boostedURL(url), outError);
}
- (id)initWithContentsOfURL:(NSURL *)url fileTypeHint:(NSString *)hint error:(NSError **)outError {
    return %orig(boostedURL(url), hint, outError);
}
- (void)setVolume:(float)volume {
    %orig(1.0f);
}
%end
%hook AVSpeechUtterance
- (void)setVolume:(float)volume {
    %orig(1.0f);
}
%end
%end

%ctor {
    @autoreleasepool {
        NSBundle *b = [NSBundle mainBundle];
        NSString *bid = b.bundleIdentifier ?: @"";
        NSString *name = [b objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [b objectForInfoDictionaryKey:@"CFBundleName"] ?: @"";
        if ([bid isEqualToString:@"com.google.Maps"]) {
            %init(MapsFix);
        } else if ([name containsString:@"神盾"]) {
            NSLog(@"[ShieldBoost] loaded in %@ (%@)", name, bid);
            %init(ShieldBoost);
        }
    }
}
