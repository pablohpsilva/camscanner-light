Feature: Scan camera permission and preview

  Scenario: Permission denied shows a rationale and a path to Settings
    Given the app is launched with camera permission denied
    When I tap the Scan button
    Then I see {'Camera access is needed to scan documents'} text
    And I see {'Open Settings'} text

  Scenario: Permission granted shows the live preview
    Given the app is launched with camera permission granted
    When I tap the Scan button
    Then I see the camera preview

  Scenario: No camera shows the unavailable message
    Given the app is launched with no camera available
    When I tap the Scan button
    Then I see {'Camera unavailable on this device'} text
