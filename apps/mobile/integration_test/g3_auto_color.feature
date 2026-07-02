Feature: G3 Color and Auto scan enhancement

  Scenario: Auto filter applied — document saved with auto enhancement
    Given the review screen is open with a captured image
    When I toggle the auto filter
    And I tap Accept
    Then the document is saved with auto enhancement

  Scenario: Color filter applied — document saved with color enhancement
    Given the review screen is open with a captured image
    When I toggle the color filter
    And I tap Accept
    Then the document is saved with color enhancement

  Scenario: No filter — document saved without enhancement
    Given the review screen is open with a captured image
    When I tap Accept
    Then the document is saved without enhancement

  Scenario: Auto filter removes the shadow from a shadowed capture
    Given the review screen is open with a captured image
    When I toggle the auto filter
    And I tap Accept
    Then the auto enhancer flattens the shadow
