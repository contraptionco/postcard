# frozen_string_literal: true

class GhostIntegrationsController < ApplicationController
  prepend_before_action :authenticate_account!
  before_action :set_account_from_path

  def update
    # This is the server operator's Contraption integration, not a shared
    # destination to which administrators can send other authors' subscribers.
    return head :forbidden unless current_account.admin? && @account == current_account

    if @account.update(params.require(:account).permit(:sync_to_ghost))
      redirect_to edit_page_path(@account), notice: 'Ghost integration updated.', status: :see_other
    else
      redirect_to edit_page_path(@account), alert: @account.errors.full_messages.to_sentence, status: :see_other
    end
  end
end
