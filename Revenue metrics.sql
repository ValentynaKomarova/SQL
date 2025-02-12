with monthly_data as
(
select 
		gp.user_id,
		gp.game_name,
		date(date_trunc('month',gp.payment_date)) as payment_month, 
		count(distinct gp.user_id) as paid_users, --порахувала платних місячних користувачів*
		sum(gp.revenue_amount_usd) as total_revenue --загальна сума доходу
from project.games_payments gp 
group by 1,2,3
),
date_slice as
(
select 
		*,
		lag(md.payment_month) over(partition by md.user_id order by md.payment_month) as first_payment_month,-- роблю зріз по попередньому місяцю платежу
		lead(md.payment_month) over(partition by md.user_id order by md.payment_month) as last_payment_month, -- роблю зріз по наступному місяцю платежу
		md.payment_month - interval '1 month' as previous_month, --інтервал в 1 місяць назад
		lag(md.total_revenue) over(partition by md.user_id order by md.payment_month) as previous_month_revenue --роблю зріз по попередньому місяці оплати
from monthly_data md
),
calculate_metrics as
(
select
		ds.user_id,
		ds.payment_month,
		case when ds.first_payment_month is null then 1 end as new_paid_users, -- користувачі, що стали платними у певний місяць*
		case when ds.first_payment_month is null then ds.total_revenue end as new_mrr, --дохід від нових платних користувачів*
		case when ds.last_payment_month is null then 1 end as churned_users, --користувачі, які припинили платити*
		case when ds.last_payment_month is null then ds.total_revenue end as churned_revenue, --сумарний дохід за попередній період від усіх користувачів, що припинили платити*
		case when ds.first_payment_month = ds.previous_month
		and ds.total_revenue < ds.previous_month_revenue
		then ds.total_revenue - ds.previous_month_revenue end as contraction_mrr,--сума, на яку зменшилася MRR від одного місяця до іншого*
		case when ds.first_payment_month = ds.previous_month
		and ds.total_revenue > ds.previous_month_revenue
		then ds.total_revenue - ds.previous_month_revenue end as expansion_mrr, -- сума, на яку збільшилася MRR від одного місяця до іншого*
		round(avg(ds.last_payment_month - ds.first_payment_month),0) as lt, --середня кількість часу від першої оплати до відвалу користувачів
		(ds.total_revenue/ds.paid_users) * round(avg(ds.last_payment_month - ds.first_payment_month),0) as ltv --середній дохід, котрий один юзер сплачує за весь час користування продуктом*
from date_slice ds
group by 1,2,3,4,5,6,7,8, ds.total_revenue,ds.paid_users
)
select 
		md.user_id,
		md.payment_month,
		md.game_name,
		md.paid_users,
		md.total_revenue as mrr,
		gpu."language" ,
		gpu.age,
		cm.new_paid_users,
		cm.new_mrr,
		cm.churned_users,
		cm.churned_revenue,
		cm.contraction_mrr,
		cm.expansion_mrr,
		cm.lt,
		cm.ltv
from monthly_data md
left join calculate_metrics cm on cm.user_id = md.user_id
		and cm.payment_month = md.payment_month
left join project.games_paid_users gpu on gpu.user_id = md.user_id
		and gpu.game_name = md.game_name
order by md.payment_month



