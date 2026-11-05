class SplitsController < ApplicationController
  # The quick split screen. It touches no database: the organizer has not asked
  # us to remember anything yet, so there is nothing to save and nothing to look
  # up. The shares on screen are worked out in the browser by QuickSplitLogic,
  # which mirrors SplitMath so the numbers move with every keystroke.
  #
  # The limits come from SplitMath rather than being written into the view, so
  # the browser and the server cannot drift apart on what "2 to 20 people" means.
  def new
    @minimum_people = SplitMath::PEOPLE_RANGE.min
    @maximum_people = SplitMath::PEOPLE_RANGE.max
    @maximum_total_cents = SplitMath::MAXIMUM_TOTAL_CENTS
    @default_people = @minimum_people
  end
end
