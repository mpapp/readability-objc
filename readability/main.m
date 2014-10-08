//
//  main.m
//  readability
//
//  Created by Jan on 23.02.12.
//  Copyright (c) 2012 geheimwerk.de. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <AppKit/AppKit.h>

#import <Webkit/Webkit.h>
#import <WebKit/WebArchive.h>

#import "KBWebArchiver.h"
#import "JXReadabilityDocument.h"
#import "JXWebResourceLoadingBarrier.h"


BOOL dumpXMLDocumentToPath(NSXMLDocument *doc, NSString *output, NSUInteger xmlOutputOptions, NSString *tag, NSError **error);


BOOL dumpXMLDocumentToPath(NSXMLDocument *doc, NSString *output, NSUInteger xmlOutputOptions, NSString *tag, NSError **error) {
	if (output == nil)  return NO;
	
	NSString *outputPath = nil;
	if (tag == nil) {
		outputPath = [[output stringByDeletingPathExtension] 
					  stringByAppendingPathExtension:@"html"];
	} else {
		outputPath = [[[output stringByDeletingPathExtension] 
					   stringByAppendingString:tag]
					  stringByAppendingPathExtension:@"html"];
	}
	
	BOOL OK;
	
	if (doc != nil)	{
		NSData *docData = [doc XMLDataWithOptions:xmlOutputOptions];
		OK = [docData writeToFile:outputPath  
						  options:NSDataWritingAtomic 
							error:error];
	}
	else {
		OK = NO;
	}
	
	return OK;
}


int main(int argc, const char * argv[])
{

	@autoreleasepool {
		NSError *error = nil;

		NSUserDefaults *args = [NSUserDefaults standardUserDefaults];	
		
		NSString *urlString = [args stringForKey:@"url"];
		NSString *localOnlyString = [args stringForKey:@"local"];
		NSString *webarchivePath = [args stringForKey:@"webarchive"];
		NSString *verboseString = [args stringForKey:@"verbose"];
		NSString *output = [args stringForKey:@"output"];
		
		BOOL localOnly = [localOnlyString isEqualToString:@"YES"];
		BOOL verbose = [verboseString isEqualToString:@"YES"];
		
		if ((urlString == nil) && (webarchivePath == nil)) {
#if 0
			NSArray *arguments = [[NSProcessInfo processInfo] arguments];
			const char *executablePath = [[arguments objectAtIndex:0] 
										  fileSystemRepresentation];
#endif
			fprintf(stderr, "readability 0.1.1\nUsage: \nreadability -url URL [-verbose YES|NO] -output FILE \n");
			
			return EXIT_FAILURE;
		}
		

		WebArchive *webarchive;
		if (webarchivePath == nil) {
			KBWebArchiver *archiver = [[KBWebArchiver alloc] initWithURLString:urlString];
			archiver.localResourceLoadingOnly = localOnly;
			webarchive = [archiver webArchive];
			NSData *data = [webarchive data];
			error = [archiver error];
			
			if ( webarchive == nil || data == nil ) {
				fprintf(stderr, "Error: Unable to create webarchive\n");
				if (error != nil)  fprintf(stderr, "%s\n", [[error description] UTF8String]);
				
				return EXIT_FAILURE;
			}
		}
		else {
			NSData *data = [NSData dataWithContentsOfFile:webarchivePath 
												  options:0 
													error:&error];
			if (data == nil) {
				fprintf(stderr, "Error: Unable to read webarchive\n");
				if (error != nil)  fprintf(stderr, "%s\n", [[error description] UTF8String]);
				
				return EXIT_FAILURE;
			}
			
			webarchive = [[WebArchive alloc] initWithData:data];
		}

		WebResource *resource = [webarchive mainResource];
		
		NSString *textEncodingName = [resource textEncodingName];
		
		NSStringEncoding encoding;
		if (textEncodingName == nil) {
			encoding = NSISOLatin1StringEncoding;
		}
		else {
			CFStringEncoding cfEnc = CFStringConvertIANACharSetNameToEncoding((CFStringRef)textEncodingName);
			if (kCFStringEncodingInvalidId == cfEnc) {
				encoding = NSUTF8StringEncoding;
			}
			else {
				encoding = CFStringConvertEncodingToNSStringEncoding(cfEnc);
			}
		}
		
		NSString *source = [[NSString alloc] initWithData:[resource data] 
												  encoding:encoding];
#if DEBUG
		if (output != nil) {
			NSString *outputRawPath = [[[output stringByDeletingPathExtension] 
										stringByAppendingString:@"-raw"]
									   stringByAppendingPathExtension:@"html"];
			BOOL OK;
			OK = [source writeToFile:outputRawPath 
						  atomically:YES 
							encoding:encoding 
							   error:&error];
			
			if (!OK && verbose) {
				NSLog(@"\n%@", error);
			}
		}
#endif

		
		NSXMLDocumentContentKind contentKind = JXReadabilityNSXMLDocumentKind;
		NSUInteger xmlOutputOptions = (contentKind 
									   //| NSXMLNodePrettyPrint
									   | NSXMLNodePreserveWhitespace 
									   | NSXMLNodeCompactEmptyElement
									   );
		
		NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:source 
															  options:NSXMLDocumentTidyHTML 
																error:&error];
#if DEBUG
		if (!dumpXMLDocumentToPath(doc, output, xmlOutputOptions, @"-tidy", &error) && verbose) {
			NSLog(@"\n%@", error);
		}
#endif
		
		NSXMLDocument *cleanedDoc = nil;
		NSXMLDocument *summaryDoc = nil;
		
		if (doc != nil) {
			[doc setDocumentContentKind:contentKind];
			
			{
				JXReadabilityDocument *readabilityDoc = [[JXReadabilityDocument alloc] initWithXMLDocument:doc
																							  copyDocument:NO];
				summaryDoc = [readabilityDoc summaryXMLDocument];
				cleanedDoc = readabilityDoc.html;
				
				//NSLog(@"\nTitle: %@", readabilityDoc.title);
				//NSLog(@"\nShort Title: %@", readabilityDoc.shortTitle);
				
			}
		}

#if DEBUG
		if (!dumpXMLDocumentToPath(cleanedDoc, output, xmlOutputOptions, @"-cleaned", &error) && verbose) {
			NSLog(@"\n%@", error);
		}
#endif
		
		if (output == nil) {
			fprintf(stdout, "%s\n", [[summaryDoc XMLString] UTF8String]);
		}
		else {
			if (!dumpXMLDocumentToPath(summaryDoc, output, xmlOutputOptions, nil, &error) && verbose) {
				NSLog(@"\n%@", error);
			}
			
			NSString *outputPathExtension = [output pathExtension];
			
			BOOL wantWebarchive;
			if ((wantWebarchive = [outputPathExtension isEqualToString:@"webarchive"]) 
				|| [outputPathExtension isEqualToString:@"rtf"]) {
				BOOL success;
				
				// Create a new webarchive with the processed markup as main content and the resources from the source webarchive 
				NSData *docData = [summaryDoc XMLDataWithOptions:xmlOutputOptions];
				WebResource *mainResource = [[WebResource alloc] initWithData:docData 
																		  URL:[resource URL] 
																	 MIMEType:[resource MIMEType]
															 textEncodingName:[resource textEncodingName] 
																	frameName:nil];
				
				WebArchive *outWebarchive = [[WebArchive alloc] initWithMainResource:mainResource 
																		subresources:[webarchive subresources] 
																	subframeArchives:[webarchive subframeArchives]];
				
				NSData *outWebarchiveData = [outWebarchive data];
				
				if (wantWebarchive) {
					success = [outWebarchiveData writeToFile:output 
													 options:NSDataWritingAtomic 
													   error:&error];
				}
				else {
					JXWebResourceLoadingBarrier *loadDelegate = [JXWebResourceLoadingBarrier new];
					loadDelegate.localResourceLoadingOnly = localOnly;
					NSDictionary *options = @{NSWebResourceLoadDelegateDocumentOption: loadDelegate};
					NSDictionary *documentAttributes = nil;
					NSAttributedString *outAttributedString = [[NSAttributedString alloc] initWithData:outWebarchiveData 
																							   options:options
																					documentAttributes:&documentAttributes 
																								 error:&error];
					if (outAttributedString != nil) {
						NSRange fullRange = NSMakeRange(0, outAttributedString.length);
						NSData *outRTFData = [outAttributedString RTFFromRange:fullRange documentAttributes:documentAttributes];
						success = [outRTFData writeToFile:output 
												  options:NSDataWritingAtomic 
													error:&error];
					}
					else {
						success = NO;
					}
					
				}
				
				if (!success) {
					NSLog(@"\n%@", error);
				}
				
				
			}
		}
		
	}
	
	return EXIT_SUCCESS;
}

