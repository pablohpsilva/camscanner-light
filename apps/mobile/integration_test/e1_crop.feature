Feature: Adjust crop corners
  Scenario: Drag a corner before saving
    Given the app is launched with camera permission granted and empty storage
    When I tap the import button
    And I see the crop overlay
    And I drag the top left crop corner
    And I tap Accept
    Then I see a saved document on the home
