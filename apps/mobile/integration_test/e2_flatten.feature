Feature: Perspective flatten
  Scenario: Flat image is shown in the page viewer after capture with adjusted corners
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I see the crop overlay
    And I drag the top left crop corner
    And I tap Accept
    Then I see a saved document on the home
    When I open the first document
    Then I see the page viewer
