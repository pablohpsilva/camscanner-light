Feature: Print a document

  Scenario: Print the open document
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I open the first document
    And I print the document
    Then I see the print confirmation
