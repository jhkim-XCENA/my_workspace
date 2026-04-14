#!/bin/bash

# jhkim_ 으로 시작하는 Docker 컨테이너를 일괄 정리하는 스크립트

CONTAINERS=$(docker ps -a --filter "name=^jhkim_" --format "{{.Names}}")

if [ -z "$CONTAINERS" ]; then
    echo "jhkim_ 컨테이너가 없습니다."
    exit 0
fi

echo "=== 삭제 대상 컨테이너 ==="
docker ps -a --filter "name=^jhkim_" --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}"
echo ""

read -p "위 컨테이너를 모두 삭제하시겠습니까? (y/N) " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "취소되었습니다."
    exit 0
fi

echo ""
for name in $CONTAINERS; do
    echo -n "  $name ... "
    docker rm -f "$name" > /dev/null 2>&1 && echo "삭제" || echo "실패"
done

echo ""
echo "완료."
