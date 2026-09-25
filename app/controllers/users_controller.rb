# /api/users (tudo admin): index, create, update, destroy — sempre escopado
# em Current.company.users (usuário de outra empresa → 404, nunca 403).
class UsersController < ApplicationController
  before_action :require_admin!
  before_action :set_user, only: [ :update, :destroy ]

  def index
    render json: { users: Current.company.users.order(:created_at).map { |user| user_payload(user) } }
  end

  def create
    user = Current.company.users.create!(create_params)
    render json: { user: user_payload(user) }, status: :created
  end

  def update
    new_role = update_params[:role]

    if new_role.present? && new_role != "admin" && last_admin?(@user)
      return render_errors([ "A empresa precisa de pelo menos um administrador." ], status: :unprocessable_content)
    end

    @user.assign_attributes(update_params)
    @user.password = params[:password] if params[:password].present?
    @user.save!

    # Trocou a senha: derruba as outras sessões do usuário (menos a atual, se for ele mesmo).
    @user.sessions.where.not(id: Current.session.id).destroy_all if params[:password].present?

    render json: { user: user_payload(@user) }
  end

  def destroy
    if @user == Current.user
      return render_errors([ "Você não pode remover o próprio usuário." ], status: :unprocessable_content)
    end

    if last_admin?(@user)
      return render_errors([ "A empresa precisa de pelo menos um administrador." ], status: :unprocessable_content)
    end

    @user.sessions.destroy_all
    @user.destroy!
    head :no_content
  end

  private

  def set_user
    @user = Current.company.users.find(params[:id])
  end

  def create_params
    params.permit(:name, :email, :password, :role)
  end

  def update_params
    params.permit(:name, :role)
  end

  def last_admin?(user)
    return false unless user.admin?

    Current.company.users.where(role: "admin").where.not(id: user.id).none?
  end
end
