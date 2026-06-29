Feature: Save a captured document

  Scenario: Accepting a capture saves it and shows it on the home
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I tap Accept
    Then I see a saved document on the home

  Scenario: A failed save keeps me on the review screen
    Given saving documents fails
    When I tap the Scan button
    And I tap the shutter
    And I tap Accept
    Then I see the save error
    And I see the capture review screen
