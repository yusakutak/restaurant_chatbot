Rails.application.routes.draw do
  # 明示的にGETルートを追加
  get '/', to: 'chat#index'
  root 'chat#index'
  
  get 'chat', to: 'chat#index'
  post 'chat', to: 'chat#create'
  post 'chat/reset', to: 'chat#reset'
end