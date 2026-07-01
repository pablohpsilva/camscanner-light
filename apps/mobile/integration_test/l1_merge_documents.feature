Feature: Merge documents

  Scenario: Merge another document into the open one
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I open the first document
    And I merge the other document
    Then I see two page thumbnails
