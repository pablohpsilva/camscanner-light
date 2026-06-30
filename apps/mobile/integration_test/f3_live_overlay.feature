Feature: F3 live edge overlay in camera preview

  Scenario: Document detected — green outline appears
    Given the camera is ready with a detector returning confident corners
    When the live overlay sample timer fires
    Then the live quad overlay is visible on the camera preview

  Scenario: No document detected — no outline shown
    Given the camera is ready with a detector returning no result
    When the live overlay sample timer fires
    Then no live quad overlay is visible on the camera preview
