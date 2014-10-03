//
//  JXReadabilityTransformer.m
//  readability
//
//  Created by Matias Piipari on 03/10/2014.
//  Copyright (c) 2014 geheimwerk.de. All rights reserved.
//

#import "JXReadabilityTransformer.h"
#import "JXReadabilityDocument.h"

#import "KBWebArchiver.h"

@implementation JXReadabilityTransformer

- (WebArchive *)readableWebArchiveForContentsOfURL:(NSURL *)URL
                                 preprocessHandler:(NSData *(^)(NSData *data))preprocessHandler
                                             error:(NSError **)error {
    WebArchive *webarchive = nil;
    if ([URL.lastPathComponent hasSuffix:@".webarchive"]) {
        NSData *data = [NSData dataWithContentsOfURL:URL options:0 error:error];
        if (!data) {
            return nil;
        }
        webarchive = [[WebArchive alloc] initWithData:data];
    }
    else { // construct a web archive out of the content if it wasn't one yet.
        KBWebArchiver *archiver = [[KBWebArchiver alloc] initWithURL:URL];
        archiver.localResourceLoadingOnly = NO;
        webarchive = archiver.webArchive;
        NSData *data = webarchive.data;
        
        if (error) {
            *error = [archiver error];
            return nil;
        }
        
        webarchive = [[WebArchive alloc] initWithData:data];
    }

    return [self readableWebArchiveForWebArchive:webarchive
                               preprocessHandler:preprocessHandler
                                           error:error];
}

- (WebArchive *)readableWebArchiveForWebArchive:(WebArchive *)webarchive
                              preprocessHandler:(NSData *(^)(NSData *data))preprocessHandler
                                          error:(NSError **)error {
    WebResource *resource = webarchive.mainResource;
    NSString *textEncodingName = resource.textEncodingName;
    
    NSStringEncoding encoding;
    if (!textEncodingName) {
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
    
    NSXMLDocument *doc = nil;
    NSXMLDocumentContentKind contentKind = NSXMLDocumentXHTMLKind;
    NSUInteger xmlOutputOptions = (contentKind
                                   //| NSXMLNodePrettyPrint
                                   | NSXMLNodePreserveWhitespace
                                   | NSXMLNodeCompactEmptyElement);
    if (preprocessHandler) {
        doc = [[NSXMLDocument alloc] initWithData:preprocessHandler(resource.data)
                                          options:xmlOutputOptions error:error];
        
        if (!doc)
            return nil;
    }
    else {
        NSString *source = [[NSString alloc] initWithData:resource.data encoding:encoding];
        doc = [[NSXMLDocument alloc] initWithXMLString:source
                                               options:NSXMLDocumentTidyHTML error:error];
    }
    
    if (!doc)
        return nil;
    
    NSXMLDocument *summaryDoc = nil;
    
    if (doc != nil) {
        [doc setDocumentContentKind:contentKind]; {
            JXReadabilityDocument *readabilityDoc
                = [[JXReadabilityDocument alloc] initWithXMLDocument:doc copyDocument:NO];
            summaryDoc = readabilityDoc.summaryXMLDocument;
        }
    }
    
    // Create a new webarchive with the processed markup as main content and the resources from the source webarchive
    NSData *docData = [summaryDoc XMLDataWithOptions:xmlOutputOptions];
    WebResource *mainResource = [[WebResource alloc] initWithData:docData
                                                              URL:resource.URL
                                                         MIMEType:resource.MIMEType
                                                 textEncodingName:resource.textEncodingName
                                                        frameName:nil];
    
    WebArchive *outWebarchive = [[WebArchive alloc] initWithMainResource:mainResource
                                                            subresources:webarchive.subresources
                                                        subframeArchives:webarchive.subframeArchives];
    
    return outWebarchive;
}

@end
