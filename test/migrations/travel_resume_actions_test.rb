require 'test_helper'
require_relative '../../db/migrate/20261104010000_create_travel_resume_actions'
require_relative '../support/travel_repair_fixtures'
class TravelResumeActionsTest < ActiveSupport::TestCase
  include TravelRepairFixtures
  setup {setup_travel_repair}
  test 'populated audit table refuses destructive rollback' do
    @user.update!(user_type:'admin')
    travel=gate_start
    travel.interdict!(100)
    ResumeInterdiction.call(id:travel.id,review_token:ResumeInterdiction.review(travel).token,
      actor:@user,reason:'Migration preservation test')
    assert_raises(ActiveRecord::IrreversibleMigration){CreateTravelResumeActions.new.migrate(:down)}
    assert_equal 1,TravelResumeAction.count
    index=ActiveRecord::Base.connection.indexes(:travel_resume_actions).find{|x|x.name=='index_one_resume_action_per_interdiction'}
    assert index.unique
    assert_equal %w[travel_guid interdiction_count],index.columns
  end
end
