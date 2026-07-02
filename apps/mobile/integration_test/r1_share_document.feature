Feature: Share a document

  Scenario: Share the saved document's PDF from the library
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I share the first document
    Then the document is handed to the share sheet
