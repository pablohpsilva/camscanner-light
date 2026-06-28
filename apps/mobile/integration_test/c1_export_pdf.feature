Feature: Export a document to PDF

  Scenario: Capture, save, then export the document to PDF
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I tap Accept
    And I open the first document
    And I export the open document to PDF
    Then the PDF is saved
