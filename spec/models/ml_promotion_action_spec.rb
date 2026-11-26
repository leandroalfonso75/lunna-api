require "rails_helper"

RSpec.describe MlPromotionAction do
  let(:account) { create(:ml_account) }
  let(:item_id) { "MLB1" }

  def act(kind, at:, ok: true, source: "rotina", effective_at: nil)
    account.ml_promotion_actions.create!(item_id: item_id, kind: kind, source: source, ok: ok, effective_at: effective_at,
                                         created_at: at, to_type: "PRICE_DISCOUNT")
  end

  describe ".pending_schedules" do
    it "mantém a troca programada sem mudança depois dela" do
      sched = act("agendar", at: 2.days.ago, effective_at: 10.days.from_now)
      act("pular", at: 1.day.ago)
      act("ajustar_preco", at: 1.hour.ago, ok: false, source: "tela") # falhou: não substitui

      expect(account.ml_promotion_actions.pending_schedules).to contain_exactly(sched)
    end

    it "uma mudança que deu certo depois (ex.: cabível pela tela) substitui a troca programada" do
      act("agendar", at: 2.days.ago, effective_at: 10.days.from_now)
      act("ajustar_preco", at: 1.hour.ago, source: "tela")

      expect(account.ml_promotion_actions.pending_schedules).to be_empty
    end

    it "simulação não substitui, e programada que já passou da hora não conta" do
      sched = act("agendar", at: 2.days.ago, effective_at: 10.days.from_now)
      act("aderir", at: 1.hour.ago, source: "simulacao")
      act("agendar", at: 5.days.ago, effective_at: 1.day.ago)

      expect(account.ml_promotion_actions.pending_schedules).to contain_exactly(sched)
    end
  end
end
