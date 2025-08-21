class AccountController < ApplicationController

def show
    @page = Page.find_by_slug('account')            

@purchase_transactions =
  Transaction.where(player_uuid: current_user.uid, transaction_type: 'purchase')
             .order(created_at: :desc)

@sell_transactions =
  Transaction.where(player_uuid: current_user.uid, transaction_type: 'sell')
             .order(created_at: :desc)


    render "pages/account"
end

def login
    @page = Page.find_by_slug('login')
    render "pages/login"

end

end