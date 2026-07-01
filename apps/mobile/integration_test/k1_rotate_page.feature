Feature: Rotate a page

  Scenario: Rotate the open page
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I open the first document
    And I rotate the page
    Then I see the page viewer
