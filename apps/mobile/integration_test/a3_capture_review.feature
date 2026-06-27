Feature: Capture a photo and review it

  Scenario: Tapping the shutter shows the review screen
    Given the app is launched with camera permission granted
    When I tap the Scan button
    And I tap the shutter
    Then I see the capture review screen

  Scenario: Retake returns to the live preview
    Given the app is launched with camera permission granted
    When I tap the Scan button
    And I tap the shutter
    And I tap Retake
    Then I see the camera preview

  Scenario: Accept returns to the Documents home
    Given the app is launched with camera permission granted
    When I tap the Scan button
    And I tap the shutter
    And I tap Accept
    Then I see the Documents home
