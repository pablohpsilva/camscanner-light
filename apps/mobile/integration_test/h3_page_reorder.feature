Feature: H3 Page reorder

  Scenario: Dragging the second thumbnail to the first position swaps the order
    Given the page viewer is open with 2 pages
    When the second page thumbnail is dragged to the first position
    Then the first visible page is position 2
