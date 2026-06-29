Feature: Sort the library
  Scenario: Switch the library sort to name
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I tap Accept
    And I tap the sort chip {'name'}
    Then I see the sort chip {'name'} is active
