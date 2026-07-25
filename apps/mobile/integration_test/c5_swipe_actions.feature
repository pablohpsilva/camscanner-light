Feature: Document list swipe actions

  Scenario: Swipe right reveals the quick actions
    Given a swipeable document list
    When I swipe the first document right
    Then I see the copy text swipe action
    And I see the protect swipe action

  Scenario: Copy text via swipe right
    Given a swipeable document list
    When I swipe the first document right
    And I tap the copy text swipe action
    Then the copy text action fired

  Scenario: Swipe left then confirm deletes
    Given a swipeable document list
    When I swipe the first document left
    And I tap the delete swipe action
    And I confirm the delete dialog
    Then the delete action fired

  Scenario: Swipe left then cancel does not delete
    Given a swipeable document list
    When I swipe the first document left
    And I tap the delete swipe action
    And I cancel the delete dialog
    Then the delete action did not fire
