Feature: G1 grayscale scan enhancement

  Scenario: Grayscale filter applied — document saved with enhancement
    Given the review screen is open with a captured image
    When I toggle the grayscale filter
    And I tap Accept
    Then the document is saved with grayscale enhancement

  Scenario: No filter — document saved without enhancement
    Given the review screen is open with a captured image
    When I tap Accept
    Then the document is saved without enhancement
