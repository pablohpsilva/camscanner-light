Feature: Preview a document as PDF

  Scenario: Capture, save, then preview the document as a PDF
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I tap Accept
    And I tap Done
    And I open the first document
    And I export the open document to PDF
    Then the PDF preview opens
