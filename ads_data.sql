-- 1. Получить статистику по дням. Просто посчитать число всех событий по дням, число показов,
-- число кликов, число уникальных объявлений и уникальных кампаний.

-- число всех событий по дням

select date, count(event) as number_of_event
    from ads_data
        group by date;

-- число показов

select countIf(event, event=='view') as number_of_view
    from ads_data;

-- число кликов

select countIf(event, event=='click') as number_of_view
    from ads_data;

-- число уникальных объявлений

select length(groupUniqArray(ad_id)) as number_of_uniq_ads
from ads_data;


-- число уникальных кампаний

select length(groupUniqArray(campaign_union_id)) as number_of_uniq_campaign
from ads_data;


-- 2.Разобраться, почему случился такой скачок 2019-04-05? Каких событий стало больше?
-- У всех объявлений или только у некоторых?

-- Количество кликов и показов больше чем в остальные дни

select date, countIf(event, event=='click')as click, countIf(event, event=='view') as view
     , count(event) as number_of_event
    from ads_data
        group by date;

-- В этот день было максимальное количество уникальных реламных кампаний и объявлений

select date, uniqExact(campaign_union_id) , uniqExact(ad_id), sum(target_audience_count)
from ads_data
group by date;

-- Рекламные кампании на которых наблюдается существенный прирост показов и кликов

select campaign_union_id, countIf(event, event=='click') as click,
       countIf(event, event=='view') as view
from ads_data
where date ='2019-04-05'
group by campaign_union_id
ORDER BY click DESC ;

-- Объявление на котором наблюдается существенный прирост показов и кликов

select ad_id, countIf(event, event=='click') as click,
       countIf(event, event=='view') as view
from ads_data
where date ='2019-04-05'
group by ad_id
ORDER BY click DESC
limit 1;



--3.Найти топ 10 объявлений по CTR за все время. CTR — это отношение всех кликов объявлений к просмотрам.
-- Например, если у объявления было 100 показов и 2 клика, CTR = 0.02.
-- Различается ли средний и медианный CTR объявлений в наших данных?

--ТОП10 объявлений по CTR

SELECT ad_id, round(countIf(event, event=='click')/countIf(event, event=='view'),2) as CTR
from ads_data
group by ad_id
HAVING countIf(event, event=='view') > 0
ORDER BY CTR DESC
LIMIT 10;

--Медиана и среднее различается. Медиана стремится к нулю, среднее - 0,016

SELECT round(avg(CTR),3) as AVG_CTR, round(quantile(0.5)(CTR),3) AS Median_CTR
    from (SELECT ad_id, countIf(event, event=='click')/countIf(event, event=='view') as CTR
from ads_data
group by ad_id
HAVING countIf(event, event=='view') > 0);


--4.Похоже, в наших логах есть баг, объявления приходят с кликами, но без показов!
-- Сколько таких объявлений, есть ли какие-то закономерности?
-- Эта проблема наблюдается на всех платформах?

--Таких 9 объявлений. Баг наблюдается на всех платформах.

SELECT ad_id, countIf(event, event=='click') as click, countIf(event, event=='view') as view,
       groupUniqArray(platform) as Platform, groupUniqArray(has_video) as has_video
from ads_data
group by ad_id
having countIf(event, event=='view')==0 and countIf(event, event=='click')>0;


--5.Есть ли различия в CTR у объявлений с видео и без?
-- А чему равняется 95 процентиль CTR по всем объявлениям за 2019-04-04?


--В объявлениях без видео в среднем CTR немного больше

select round(avg(CTR_without_video),3) as avg_ctr, round(quantile(0.25)(CTR_without_video),3) AS procentile_25,
      round(quantile(0.5)(CTR_without_video),3) AS median, round(quantile(0.75)(CTR_without_video),3) AS procentile_75
from (SELECT ad_id, countIf(event, event=='click')/countIf(event, event=='view' ) as CTR_without_video
from ads_data
where has_video=0
group by ad_id
HAVING countIf(event, event=='view') > 0)
union all
select round(avg(CTR_with_video),3) as avg_ctr, round(quantile(0.25)(CTR_with_video),3) AS procentile_25,
      round(quantile(0.5)(CTR_with_video),3) AS median, round(quantile(0.75)(CTR_with_video),3) AS procentile_75
from (SELECT ad_id, countIf(event, event=='click')/countIf(event, event=='view' ) as CTR_with_video
from ads_data
where has_video=1
group by ad_id
HAVING countIf(event, event=='view') > 0);


--тоже, только с группировкой по has_video

select round(avg(CTR),3) as avg_ctr, round(quantile(0.25)(CTR),3) AS procentile_25,
      round(quantile(0.5)(CTR),3) AS median, round(quantile(0.75)(CTR),3) AS procentile_75
          from (
SELECT has_video, ad_id, countIf(event, event=='click')/countIf(event, event=='view' ) as CTR
from ads_data
group by has_video, ad_id
HAVING countIf(event, event=='view')>0)
group by has_video;

--95 процентиль CTR по всем объявлениям за 2019-04-04 равен 0,082

SELECT round(quantile(0.95)(CTR),3)
from
    (SELECT ad_id, countIf(event, event=='click')/countIf(event, event=='view' ) as CTR
        from ads_data
        where date='2019-04-04'
        group by ad_id
        HAVING countIf(event, event=='view') > 0);


-- 6.Для финансового отчета нужно рассчитать наш заработок по дням.
-- В какой день мы заработали больше всего? В какой меньше?
-- Мы списываем с клиентов деньги, если произошел клик по CPC объявлению,
-- и мы списываем деньги за каждый показ CPM объявления, если у CPM объявления цена - 200 рублей,
-- то за один показ мы зарабатываем 200 / 1000.

--Самый большой заработок 2019-04-05

select date, round(sum(if(CPM > 0, CPM*cost/1000, CPC*cost)),2) as profit
    from
(select date as date, ad_id, countIf(event, event=='view' and ad_cost_type=='CPM') as CPM,
       countIf(event, event=='click' and ad_cost_type=='CPC') as CPC,
       arrayElement(groupArray(ad_cost),1) as cost
    from ads_data
        group by ad_id, date)
group by date;

--тоже самое, более простой скрипт

select date,
       sum(multiIf((event = 'view' and ad_cost_type = 'CPM'), ad_cost / 1000,
                   (event = 'click' and ad_cost_type = 'CPC'), ad_cost, 0)) as money
from ads_data
group by date;


--7.Какая платформа самая популярная для размещения рекламных объявлений?
-- Сколько процентов показов приходится на каждую из платформ (колонка platform)?

-- самая популярная платформа - android

select platform, count(ad_id) as ads
from ads_data
group by platform
ORDER BY ads desc;

--проценты показов на каждую платформу

with (select countIf(event, event=='view') from ads_data) as sum_view
select platform, round(countIf(event, event=='view')/sum_view*100, 1) as fraction
from ads_data
group by platform
order by fraction desc;


--8.А есть ли такие объявления, по которым сначала произошел клик, а только потом показ?

-- Есть, таких 11 объявлений.

select ad_id, groupArray(event), groupArray(time)
    from
(select ad_id, event, time
    from ads_data
    order by time)
group by ad_id
having arrayElement(groupArray(event),1)='click' and arrayElement(groupArray(event),2)='view';




