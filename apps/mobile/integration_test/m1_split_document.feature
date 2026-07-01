Feature: Split a document

  Scenario: Split after the first page
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I capture and accept the second page
    And I tap Done
    And I open the first document
    And I split after the first page
    Then I see the split confirmation
