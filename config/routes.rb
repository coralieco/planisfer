Rails.application.routes.draw do
  devise_for :members,
    controllers: { omniauth_callbacks: 'members/omniauth_callbacks' }
  root to: 'pages#home'
  resources :searches, only: [:create, :show]
  resources :trips, only: [:index, :show, :update, :create]do
    get :refresh_map, to: "searches#refresh_map"
  end
  resources :round_trip_flights, only: [:create]
  resources :selections, only: [:create, :show]
  resources :airports, only: [:show] do
    get :highlight_airport, to: "searches#highlight_airport"
  end
  resources :orders, only: [:show, :create, :update] do
    resources :payments, only: [:new, :create]
  end
  get :add_question, to: "orders#add_question_to_order"
  resources :pois, only: [:show] do
    get :highlight_poi, to: "searches#highlight_poi"
  end
  resources :activities, only: [:create, :update]
  resources :experiences, only: [:create, :index, :update] do
    resources :subexperiences, only: [:new, :create]
    get :delete_subexp, to: "subexperiences#destroy"
  end
  get :create_experiences, to: "experiences#create_experiences"
  get :profile, to: "profiles#show"
  patch :update_member_recos, to: "experiences#update_recos"
  get :recommendations, to: "recommendations#show"


  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
