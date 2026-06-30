Feature: G4 Filter picker strip

  Scenario: Filter picker strip is visible on the review screen
    Given the review screen is open with a captured image
    Then I see the filter picker strip

  Scenario: Auto filter is selected by default
    Given the review screen is open with a captured image
    When I tap Accept
    Then the document is saved with auto enhancement

  Scenario: Tapping Grayscale tile saves with GrayscaleEnhancer
    Given the review screen is open with a captured image
    When I tap the grayscale filter tile
    And I tap Accept
    Then the document is saved with grayscale enhancement

  Scenario: Tapping Original tile saves without enhancement
    Given the review screen is open with a captured image
    When I tap the original filter tile
    And I tap Accept
    Then the document is saved without enhancement
