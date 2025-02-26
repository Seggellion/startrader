class AccountController < ApplicationController

def show
    @page = Page.find_by_slug('account')            

    @purchase_transactions = Transaction.where("REPLACE(player_uuid, '-', '') = ? AND transaction_type = ?", current_user.minecraft_uuid.delete('-'), 'purchase').order(created_at: :desc)
    @sell_transactions = Transaction.where("REPLACE(player_uuid, '-', '') = ? AND transaction_type = ?", current_user.minecraft_uuid.delete('-'), 'sell').order(created_at: :desc)
    

    render "pages/account"
end

def login
    @page = Page.find_by_slug('login')
    render "pages/login"

end

end