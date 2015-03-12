//
//  RMLogFormatter.m
//
//  Created by Ryan Maloney on 9/6/14.
//  Copyright (c) 2014 Ryan Maloney
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

#import <libkern/OSAtomic.h>

#import "RMLogFormatter.h"

static const NSUInteger RMLogFormatterMinimumLineLength = 80;
static const NSUInteger RMLogFormatterDefaultLineLength = 120;
static const RMLogFormatterOptions RMLogFormatterDefaultOptions =   RMLogFormatterOptionsNone |
                                                                    RMLogFormatterOptionsWordWrap |
                                                                    RMLogFormatterOptionsTimestampLong |
                                                                    RMLogFormatterOptionsFileName |
                                                                    RMLogFormatterOptionsLineNumber |
                                                                    RMLogFormatterOptionsThreadID;

@implementation RMLogFormatter {
    int _atomicLoggerCount;
    
    RMLogFormatterOptions _logOptions;
    NSUInteger _lineLength;
    
    NSString *_logStatsFormatString;
    
    NSString *_dateFormatString;
    NSDateFormatter *_threadUnsafeDateFormatter;
}

#pragma mark - Initializers

- (instancetype)init {
    return [self initWithLogLineLength:RMLogFormatterDefaultLineLength options:RMLogFormatterDefaultOptions];
}

- (instancetype)initWithLogLineLength:(NSUInteger)logLineLength {
    return [self initWithLogLineLength:logLineLength options:RMLogFormatterDefaultOptions];
}

- (instancetype)initWithOptions:(RMLogFormatterOptions)options {
    return [self initWithLogLineLength:RMLogFormatterDefaultLineLength options:options];
}

- (instancetype)initWithLogLineLength:(NSUInteger)logLineLength options:(RMLogFormatterOptions)options {
    if (self = [super init]) {
        _logOptions = options;
        _lineLength = (logLineLength < RMLogFormatterMinimumLineLength) ? RMLogFormatterMinimumLineLength : logLineLength;
        
        _logStatsFormatString = [self logStatFormatStringFromLogFormatterOptions:_logOptions];
        
        if (_logOptions & (RMLogFormatterOptionsTimestampShort | RMLogFormatterOptionsTimestampLong)) {
            if (_logOptions & RMLogFormatterOptionsTimestampShort) {
                _dateFormatString = @"HH:mm:ss.SSS";
            } else {
                _dateFormatString = @"yyyy-MM-dd HH:mm:ss.SSS";
            }
        } else {
            _dateFormatString = nil;
        }
    }
    
    return self;
}

#pragma mark - Public Property Accessors

- (RMLogFormatterOptions)options {
    return _logOptions;
}

- (NSUInteger)lineLength {
    return _lineLength;
}

- (BOOL)isTimestampEnabled {
    return !!(_logOptions & (RMLogFormatterOptionsTimestampShort | RMLogFormatterOptionsTimestampLong));
}

- (BOOL)isLogFlagEnabled {
    return !!(_logOptions & (RMLogFormatterOptionsLogFlagShort | RMLogFormatterOptionsLogFlagLong));
}

- (BOOL)isFileNameEnabled {
    return !!(_logOptions & RMLogFormatterOptionsFileName);
}

- (BOOL)isMethodNameEnabled {
    return !!(_logOptions & RMLogFormatterOptionsMethodName);
}

- (BOOL)isLineNumberEnabled {
    return !!(_logOptions & RMLogFormatterOptionsLineNumber);
}

- (BOOL)isThreadNameEnabled {
    return !!(_logOptions & RMLogFormatterOptionsThreadName);
}

- (BOOL)isThreadIDEnabled {
    return !!(_logOptions & RMLogFormatterOptionsThreadID);
}

#pragma mark - Private

- (NSString *)stringFromDate:(NSDate *)date {
    int32_t loggerCount = OSAtomicAdd32(0, &_atomicLoggerCount);
    
    if (loggerCount <= 1) {
        // Single-threaded mode.
        
        if (_threadUnsafeDateFormatter == nil) {
            _threadUnsafeDateFormatter = [[NSDateFormatter alloc] init];
            [_threadUnsafeDateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
            [_threadUnsafeDateFormatter setDateFormat:_dateFormatString];
        }
        
        return [_threadUnsafeDateFormatter stringFromDate:date];
    } else {
        // Multi-threaded mode.
        // NSDateFormatter is NOT thread-safe.
        
        NSString *key = @"RMInfoFormatter_NSDateFormatter";
        
        NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
        NSDateFormatter *dateFormatter = [threadDictionary objectForKey:key];
        
        if (dateFormatter == nil) {
            dateFormatter = [[NSDateFormatter alloc] init];
            [dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
            [dateFormatter setDateFormat:_dateFormatString];
            
            [threadDictionary setObject:dateFormatter forKey:key];
        }
        
        return [dateFormatter stringFromDate:date];
    }
}

- (NSString *)stringByRepeatingCharacter:(char)character length:(NSUInteger)length {
    char stringUtf8[length + 1];
    memset(stringUtf8, character, length * sizeof(*stringUtf8));
    stringUtf8[length] = '\0';
    
    return [NSString stringWithUTF8String:stringUtf8];
}

- (NSString *)wrapString:(NSString *)sourceString withLineLength:(NSUInteger)length indentLength:(NSUInteger)indentLength {
    BOOL isMultiline = ((sourceString.length > length) || [sourceString containsString:@"\n"]);
    
    if (!isMultiline) {
        return sourceString;
    }
    
    NSUInteger maxLineLength = length;
    
    NSString *indentString = [NSString stringWithFormat:@"\n%@", [self stringByRepeatingCharacter:' ' length:indentLength]];
    
    NSMutableString *resultString = [[NSMutableString alloc] init];
    NSMutableString *currentLine = [[NSMutableString alloc] init];
    NSScanner *scanner = [NSScanner scannerWithString:sourceString];
    scanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString:@""];
    NSString *scannedString = nil;
    while ([scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString: &scannedString]) {
        if ([currentLine length] + [scannedString length] <= maxLineLength) {
            [currentLine appendString:scannedString];
        }
        else if ([currentLine length] == 0) { // Newline but next word > currentLineLength
            [resultString appendFormat:@"%@%@", scannedString, [scanner isAtEnd] ? @"" : indentString];
            maxLineLength = length - indentLength;
        }
        else { // Need to break line and start new one
            [resultString appendFormat:@"%@%@", currentLine, [scanner isAtEnd] ? @"" : indentString];
            [currentLine setString:[NSString stringWithString:scannedString]];
            maxLineLength = length - indentLength;
        }
        
        if ([scanner scanUpToCharactersFromSet:[[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet] intoString:&scannedString]) {
            if ([scannedString containsString:@"\n"]) {
                [currentLine appendString:[scannedString stringByReplacingOccurrencesOfString:@"\n" withString:indentString]];
                [resultString appendString:currentLine];
                [currentLine setString:@""];
                maxLineLength = length - indentLength;
            } else {
                [currentLine appendString:scannedString];
            }
        }
    }
    
    [resultString appendString:currentLine];
    
    return resultString;
}

#pragma mark - Log Stat String Builders

- (NSString *)logStatFormatStringFromLogFormatterOptions:(RMLogFormatterOptions)options {
    NSMutableString *formatString = [NSMutableString string];
    
    BOOL timestampEnabled   = options & (RMLogFormatterOptionsTimestampShort | RMLogFormatterOptionsTimestampLong);
    BOOL logFlagEnabled     = options & (RMLogFormatterOptionsLogFlagShort | RMLogFormatterOptionsLogFlagLong);
    BOOL fileNameEnabled    = options & RMLogFormatterOptionsFileName;
    BOOL methodNameEnabled  = options & RMLogFormatterOptionsMethodName;
    BOOL lineNumberEnabled  = options & RMLogFormatterOptionsLineNumber;
    BOOL threadNameEnabled  = options & RMLogFormatterOptionsThreadName;
    BOOL threadIDEnabled    = options & RMLogFormatterOptionsThreadID;
    
    if (timestampEnabled) {
        [formatString appendString:@"%@"];
    }
    
    if (logFlagEnabled) {
        if (timestampEnabled) {
            [formatString appendString:@" | %@"];
        } else {
            [formatString appendString:@"%@"];
        }
    }
    
    if (fileNameEnabled) {
        if (timestampEnabled | logFlagEnabled) {
            [formatString appendString:@" | %@"];
        } else {
            [formatString appendString:@"%@"];
        }
    }
    
    if (methodNameEnabled) {
        if (fileNameEnabled) {
            [formatString appendString:@".%@"];
        } else if (timestampEnabled | logFlagEnabled) {
            [formatString appendString:@" | %@"];
        } else {
            [formatString appendString:@"%@"];
        }
    }
    
    if (lineNumberEnabled) {
        if (fileNameEnabled | methodNameEnabled) {
            [formatString appendString:@":%@"];
        } else if (timestampEnabled | logFlagEnabled) {
            [formatString appendString:@" | Line:%@"];
        } else {
            [formatString appendString:@"Line:%@"];
        }
    }
    
    if (threadNameEnabled) {
        if (fileNameEnabled | methodNameEnabled | lineNumberEnabled) {
            [formatString appendString:@" Thread:%@"];
        } else if (timestampEnabled | logFlagEnabled) {
            [formatString appendString:@" | Thread:%@"];
        } else {
            [formatString appendString:@"Thread:%@"];
        }
    }
    
    if (threadIDEnabled) {
        if (threadNameEnabled) {
            [formatString appendString:@"(%@)"];
        } else if (fileNameEnabled | methodNameEnabled | lineNumberEnabled) {
            [formatString appendString:@" (TID:%@)"];
        } else if (timestampEnabled | logFlagEnabled) {
            [formatString appendString:@" | (TID:%@)"];
        } else {
            [formatString appendString:@"(TID:%@)"];
        }
    }
    
    return [formatString copy];
}

- (NSString *)stringFromLogFlag:(DDLogFlag)logFlag {
    BOOL shortLogFlagFormat = (_logOptions & RMLogFormatterOptionsLogFlagShort) == RMLogFormatterOptionsLogFlagShort;
    
    NSString *logFlagString;
    
    switch (logFlag) {
        case DDLogFlagError:
            logFlagString = shortLogFlagFormat ? @"E" : @"  Error";
            break;
        case DDLogFlagWarning:
            logFlagString = shortLogFlagFormat ? @"W" : @"   Warn";
            break;
        case DDLogFlagInfo:
            logFlagString = shortLogFlagFormat ? @"I" : @"   Info";
            break;
        case DDLogFlagDebug:
            logFlagString = shortLogFlagFormat ? @"D" : @"  Debug";
            break;
        case DDLogFlagVerbose:
            logFlagString = shortLogFlagFormat ? @"V" : @"Verbose";
            break;
    }

    return logFlagString;
}

- (NSString *)logStatsStringFromComponents:(NSArray *)components {
    return [NSString stringWithFormat:_logStatsFormatString,    components.count>0 ? components[0] : nil,
                                                                components.count>1 ? components[1] : nil,
                                                                components.count>2 ? components[2] : nil,
                                                                components.count>3 ? components[3] : nil,
                                                                components.count>4 ? components[4] : nil,
                                                                components.count>5 ? components[5] : nil,
                                                                components.count>6 ? components[6] : nil];
}

#pragma mark - DDLogFormatter Protocol

- (NSString *)formatLogMessage:(DDLogMessage *)logMessage {
    if (_logOptions == RMLogFormatterOptionsNone) {
        return [NSString stringWithFormat:@"%@", logMessage.message];
    }
    
    NSMutableArray *logStatsComponents = [NSMutableArray array];
    
    if ([self isTimestampEnabled]) {
        [logStatsComponents addObject:[self stringFromDate:logMessage.timestamp]];
    }
    
    if ([self isLogFlagEnabled]) {
        [logStatsComponents addObject:[self stringFromLogFlag:logMessage.flag]];
    }
    
    if ([self isFileNameEnabled]) {
        [logStatsComponents addObject:logMessage.fileName];
    }
    
    if ([self isMethodNameEnabled]) {
        [logStatsComponents addObject:logMessage.function];
    }
    
    if ([self isLineNumberEnabled]) {
        [logStatsComponents addObject:[NSString stringWithFormat:@"%lu", (unsigned long)logMessage.line]];
    }
    
    if ([self isThreadNameEnabled]) {
        if (logMessage.threadName.length) {
            [logStatsComponents addObject:logMessage.threadName];
        } else {
            [logStatsComponents addObject:@"no_name"];
        }
    }
    
    if ([self isThreadIDEnabled]) {
        [logStatsComponents addObject:logMessage.threadID];
    }
    
    NSString *logStatsString = [self logStatsStringFromComponents:logStatsComponents];
    
    NSString *fullLogMessage = [NSString stringWithFormat:@"%@ : %@", logStatsString, logMessage.message];
    
    if (_logOptions & RMLogFormatterOptionsWordWrap) {
        // FIXME: If indentLength is longer than _lineLength word wrap over-indents.
        NSUInteger indentLength = logStatsString.length + 3;
        
        fullLogMessage = [self wrapString:fullLogMessage withLineLength:_lineLength indentLength:indentLength];
    }
    
    return fullLogMessage;
}

- (void)didAddToLogger:(id <DDLogger>)logger {
    OSAtomicIncrement32(&_atomicLoggerCount);
}

- (void)willRemoveFromLogger:(id <DDLogger>)logger {
    OSAtomicDecrement32(&_atomicLoggerCount);
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"RMLogFormatter description:\n%@ lineLength: %zd\noptions: %lu\ntimestampEnabled: %i\nlogFlagEnabled: %i\nfileNameEnabled: %i\nmethodNameEnabled: %i\nlineNumberEnabled: %i\nthreadNameEnabled: %i\nthreadIDEnabled: %i\n",[super description], self.lineLength, self.options, self.timestampEnabled, self.logFlagEnabled, self.fileNameEnabled, self.methodNameEnabled, self.lineNumberEnabled, self.threadNameEnabled, self.threadIDEnabled];
}

@end
