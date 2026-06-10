import Foundation
import Testing
@testable import BrainDump

@MainActor
struct URLMetadataParserTests {
    @Test
    func parsesTitleDescriptionAndOpenGraphTags() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Example Domain</title>
            <meta name="description" content="A page used for examples.">
            <meta property="og:title" content="Example OG Title" />
            <meta property="og:description" content="An OG description." />
            <meta property="og:image" content="https://example.com/image.png" />
        </head>
        <body><p>Hello</p></body>
        </html>
        """

        let metadata = URLMetadataParser.parse(html: html)

        #expect(metadata.title == "Example Domain")
        #expect(metadata.description == "A page used for examples.")
        #expect(metadata.ogTitle == "Example OG Title")
        #expect(metadata.ogDescription == "An OG description.")
        #expect(metadata.ogImage == "https://example.com/image.png")
        #expect(metadata.bestTitle == "Example OG Title")
        #expect(metadata.bestDescription == "An OG description.")
        #expect(metadata.contentText == "Example OG Title\nAn OG description.")
    }

    @Test
    func handlesMissingTagsGracefully() {
        let metadata = URLMetadataParser.parse(html: "<html><body><p>No metadata here</p></body></html>")

        #expect(metadata.title == nil)
        #expect(metadata.description == nil)
        #expect(metadata.ogTitle == nil)
        #expect(metadata.ogDescription == nil)
        #expect(metadata.ogImage == nil)
        #expect(metadata.bestTitle == nil)
        #expect(metadata.contentText.isEmpty)
        #expect(metadata.metadataJSON == "{}")
    }

    @Test
    func fallsBackToPlainTitleAndDescription() {
        let html = "<head><title>Plain Title</title><meta name=\"description\" content=\"Plain description\"></head>"

        let metadata = URLMetadataParser.parse(html: html)

        #expect(metadata.bestTitle == "Plain Title")
        #expect(metadata.bestDescription == "Plain description")
        #expect(metadata.contentText == "Plain Title\nPlain description")
    }

    @Test
    func parsesAttributesInAnyOrderQuoteStyleAndCase() {
        let html = """
        <head>
        <META CONTENT='Reversed order' PROPERTY='og:title'>
        <meta content="Named description" NAME="Description">
        <TITLE id="page-title">Upper Tag</TITLE>
        </head>
        """

        let metadata = URLMetadataParser.parse(html: html)

        #expect(metadata.ogTitle == "Reversed order")
        #expect(metadata.description == "Named description")
        #expect(metadata.title == "Upper Tag")
    }

    @Test
    func decodesEntitiesAndCollapsesWhitespace() {
        let html = """
        <title>
            Tom &amp; Jerry &#169;
            Home &gt; Index
        </title>
        <meta name="description" content="Say &quot;hello&quot; to &#x41;ll">
        """

        let metadata = URLMetadataParser.parse(html: html)

        #expect(metadata.title == "Tom & Jerry © Home > Index")
        #expect(metadata.description == "Say \"hello\" to All")
    }

    @Test
    func ignoresEmptyContentAndKeepsFirstValue() {
        let html = """
        <head>
        <meta property="og:title" content="">
        <meta property="og:title" content="First real title">
        <meta property="og:title" content="Second title">
        <title></title>
        </head>
        """

        let metadata = URLMetadataParser.parse(html: html)

        #expect(metadata.ogTitle == "First real title")
        #expect(metadata.title == nil)
    }

    @Test
    func metadataJSONContainsParsedFields() throws {
        let html = """
        <head>
        <title>JSON Page</title>
        <meta property="og:image" content="https://example.com/og.png">
        </head>
        """

        let metadata = URLMetadataParser.parse(html: html)
        let object = try JSONSerialization.jsonObject(with: Data(metadata.metadataJSON.utf8)) as? [String: String]

        #expect(object?["title"] == "JSON Page")
        #expect(object?["og_image"] == "https://example.com/og.png")
        #expect(object?["description"] == nil)
    }

    @Test
    func leavesUnknownEntitiesAndStrayAmpersandsIntact() {
        let html = "<title>Fish &chips; AT&T &unknownentity12345; end</title>"

        let metadata = URLMetadataParser.parse(html: html)

        #expect(metadata.title == "Fish &chips; AT&T &unknownentity12345; end")
    }
}
