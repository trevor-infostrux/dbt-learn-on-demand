with 

-- Import CTE's

customers as (

    select * from {{ source('jaffle_shop', 'customers') }}

),

orders as (

    select * from {{ source('jaffle_shop', 'orders') }}

),

payments as (

    select * from {{ source('stripe', 'payment') }}

), 

-- Logical CTE's 

completed_payments as (
    select 
        orderid as order_id, 
        max(created) as payment_finalized_date, 
        sum(amount) / 100.0 as total_amount_paid
    from payments
    where status <> 'fail'
    group by 1
),

paid_orders as (
        select 
            orders.id as order_id,
            orders.user_id	as customer_id,
            orders.order_date as order_placed_at,
            orders.status as order_status,
            completed_payments.total_amount_paid,
            completed_payments.payment_finalized_date,
            customers.first_name as customer_first_name,
            customers.last_name as customer_last_name
        from orders
        left join completed_payments on orders.id = completed_payments.order_id
        left join customers on orders.user_id = customers.id 
),

/* customer_orders as (
    select 
        customers.id as customer_id
        , min(orders.order_date) as first_order_date
        , max(orders.order_date) as most_recent_order_date
        , count(orders.id) as number_of_orders
    from customers 
    left join orders on orders.user_id = customers.id 
    group by 1
), */

-- Final CTE

final as (
    select
        paid_orders.order_id,
        paid_orders.customer_id,
        paid_orders.order_placed_at,
        paid_orders.order_status,
        paid_orders.total_amount_paid,
        paid_orders.payment_finalized_date,
        paid_orders.customer_first_name,
        paid_orders.customer_last_name,

        -- sales transaction sequence
        row_number() over (order by paid_orders.order_id) as transaction_seq,

        --customer sales sequence
        row_number() over (partition by paid_orders.customer_id order by paid_orders.order_id) as customer_sales_seq,

        -- new vs returning
        /* case when customer_orders.first_order_date = paid_orders.order_placed_at
        then 'new' */
        case 
            when (
                rank() over (
                    partition by customer_id order by order_placed_at, order_id
                ) = 1
            ) then 'new'
        else 'return' end as nvsr,
        
        --customer lifetime value
        sum(total_amount_paid) over(
            partition by paid_orders.customer_id
            order by paid_orders.order_placed_at
        ) as customer_lifetime_value,

        first_value(paid_orders.order_placed_at) over (
            partition by paid_orders.customer_id
            order by paid_orders.order_placed_at
        ) as fdos
    from paid_orders
)

-- Simple Select Statement

select * from final
order by order_id