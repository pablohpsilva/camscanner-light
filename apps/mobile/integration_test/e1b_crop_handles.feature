Feature: E1b Every crop handle moves the quad

  e1_crop drags only the top-left corner, so five of CropOverlay's eight
  emitNew branches had no test: the two right-hand corners and the right,
  bottom and left edge midpoints. The midpoints are the interesting ones —
  they emit a DEVIATION from the edge centre (topMidDev and friends), which is
  what bends an edge for a curved-page warp rather than just moving a quad
  vertex.

  Scenario: Dragging all four corners still saves
    Given the app is launched with camera permission granted and empty storage
    When I tap the import button
    And I see the crop overlay
    And I drag the crop handle {'tl'}
    And I drag the crop handle {'tr'}
    And I drag the crop handle {'br'}
    And I drag the crop handle {'bl'}
    And I tap Accept
    Then I see a saved document on the home

  Scenario: Dragging all four edge midpoints still saves
    Given the app is launched with camera permission granted and empty storage
    When I tap the import button
    And I see the crop overlay
    And I drag the crop handle {'top'}
    And I drag the crop handle {'right'}
    And I drag the crop handle {'bottom'}
    And I drag the crop handle {'left'}
    And I tap Accept
    Then I see a saved document on the home
