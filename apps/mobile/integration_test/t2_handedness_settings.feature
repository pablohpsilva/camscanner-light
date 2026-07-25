Feature: Choose the scan-button handedness

  Scenario: Left-handed puts the Scan button on the left
    Given the app is launched with camera permission granted and empty storage
    When I open settings from home
    And I select left-handed
    And I navigate back to home
    Then the scan button is on the left

  Scenario: Right-handed puts the Scan button on the right
    Given the app is launched with camera permission granted and empty storage
    When I open settings from home
    And I select right-handed
    And I navigate back to home
    Then the scan button is on the right
