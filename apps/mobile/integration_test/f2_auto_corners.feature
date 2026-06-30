Feature: Auto-fill crop corners

  Scenario: Document detected — corners pre-filled and overlay turns green
    Given the app is launched with a fake detector that returns detected corners
    When I tap the shutter
    Then I see the crop overlay with green handles

  Scenario: No document detected — full-frame corners and blue overlay
    Given the app is launched with a fake detector that returns null
    When I tap the shutter
    Then I see the crop overlay with blue handles
