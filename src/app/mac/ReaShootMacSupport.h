#pragma once

#import <Foundation/Foundation.h>

#include <string>

NSString *nsString(const std::string &value);
std::string stdString(NSString *value);
void debugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void initializeDebugLogging(int argc, const char *argv[]);
std::string localComputerName();
