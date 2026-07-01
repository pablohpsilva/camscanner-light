Feature: Export all pages as images

  Scenario: Exporting all pages of the open document saves them as images
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I open the first document
    And I export all pages as images
    Then I see the all images export confirmation
