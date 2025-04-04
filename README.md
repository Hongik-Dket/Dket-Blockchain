# Dket-Blockchain

## 📌 Commit Convention
- `feat`: 새로운 기능 추가  
- `fix`: 버그 수정  
- `docs`: 문서 수정  
- `style`: 코드 포맷팅, 세미콜론 누락, 코드 변경 없음  
- `refactor`: 코드 리팩토링  
- `test`: 테스트 코드 추가  
- `chore`: 빌드 업무 수정, 패키지 매니저 수정  

## 💡 PR Convention
| 아이콘 | 코드 | 설명 |
|--------|------|------|
| 🎨 | `:art:` | 코드의 구조/형태 개선 |
| ⚡ | `:zap:` | 성능 개선 |
| 🔥 | `:fire:` | 코드/파일 삭제 |
| 🐛 | `:bug:` | 버그 수정 |
| 🚑 | `:ambulance:` | 긴급 수정 |
| ✨ | `:sparkles:` | 새 기능 |
| 💄 | `:lipstick:` | UI/스타일 파일 추가/수정 |
| ⏪ | `:rewind:` | 변경 내용 되돌리기 |
| 🔀 | `:twisted_rightwards_arrows:` | 브랜치 합병 |
| 💡 | `:bulb:` | 주석 추가/수정 |

---

1. main과 release 브랜치는 확인 후에만 커밋이 가능하다. ( free 버전 private라서 잠가놓지는 못했음 )
   
2. 브랜치는 아래와 같이 총 5개이다.
  - main : 배포 가능한 최종 버전. 직접 커밋 금지. ( 실제 서버 )
  - release : 배포 가능한 최종 버전. 직접 커밋 금지. ( 예비 서버 → main 손상 시 사용 )
  - develop : 통합 테스트용 브랜치.
  - feat/ : 기능 개발 브랜치. 각 기능별로 생성해서 사용한다. (ex. `feat/login` )
  - hotfix/ : 긴급 수정 브랜치 (ex. `hotfix/bug-fix` )
    
3. ci 규칙
    - main 또는 release 브랜치로 PR 할 때만 CI가 실행되도록 설정
    
4. cd 규칙
    - main 혹은 release 브랜치로 Push 할 때만 배포가 실행되도록 설정
