Feature: G2 B&W scan enhancement

  Scenario: B&W filter applied — document saved with binarization
    Given the review screen is open with a captured image
    When I toggle the black and white filter
    And I tap Accept
    Then the document is saved with black and white enhancement

  Scenario: No filter — document saved without enhancement
    Given the review screen is open with a captured image
    When I tap Accept
    Then the document is saved without enhancement
