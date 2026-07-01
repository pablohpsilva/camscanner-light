Feature: H2 Page thumbnail strip

  Scenario: Thumbnail strip is visible on a multi-page document
    Given the page viewer is open with 2 pages
    Then I see the page thumbnail strip

  Scenario: Tapping a thumbnail navigates to that page
    Given the page viewer is open with 2 pages
    When I tap the second page thumbnail
    Then the viewer has navigated to page 2
