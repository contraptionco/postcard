# frozen_string_literal: true

class SubscribersImportsController < ApplicationController
  prepend_before_action :authenticate_account!
  before_action :set_account_from_path
  before_action :enforce_admin, only: %i[update]
  layout 'dashboard_container'

  def index
    @subscribers_imports = @account.subscribers_imports.order(created_at: :desc)
  end

  def new
    @subscribers_import = SubscribersImport.new
  end

  def create
    @subscribers_import = SubscribersImport.new(subscribers_import_params)
    @subscribers_import.account = @account

    if @subscribers_import.save
      notice = Rails.configuration.solo_mode ? 'Import completed successfully' : 'Import processing'
      redirect_to page_subscribers_imports_path(@account), notice: notice
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @subscribers_import = @account.subscribers_imports.find(params[:id])
    @subscribers_import.approved = params[:approved] == 'true' if params[:approved].present?
    @subscribers_import.save!
    redirect_to page_subscribers_imports_path(@account), notice: 'Done'
  end

  private

  def subscribers_import_params
    params.require(:subscribers_import).permit(:file, :sources_description)
  end

  def enforce_admin
    head :forbidden unless current_account&.admin?
  end
end
