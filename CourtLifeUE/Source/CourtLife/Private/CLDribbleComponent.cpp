#include "CLDribbleComponent.h"

#include "Animation/AnimInstance.h"
#include "CLAssets.h"
#include "CLCoreBridge.h"
#include "Components/SkeletalMeshComponent.h"
#include "GameFramework/Character.h"

UCLDribbleComponent::UCLDribbleComponent()
{
	PrimaryComponentTick.bCanEverTick = true;
}

void UCLDribbleComponent::Configure(const FMyPlayerBuild& InBuild, UCLAnimSet* InAnimSet)
{
	Build = InBuild;
	AnimSet = InAnimSet;
}

bool UCLDribbleComponent::StartCombo(int32 Slot)
{
	if (bActive) return false;
	const FCLDribbleCombo* Combo = Build.Combos.FindByPredicate([Slot](const FCLDribbleCombo& C) { return C.Slot == Slot; });
	if (!Combo) return false;
	Timeline = courtlife::BuildComboTimeline(CLBridge::ToCore(*Combo), CLBridge::Rating(Build, courtlife::Attr::BallHandle), CLBridge::ToCore(BallHand));
	if (Timeline.segments.empty()) return false;
	const AActor* Owner = GetOwner();
	StartLocation = Owner->GetActorLocation();
	StartFacing = Owner->GetActorRotation();
	ActiveName = Combo->Name;
	ElapsedMs = 0.f;
	PlayingSegment = INDEX_NONE;
	bActive = true;
	return true;
}

void UCLDribbleComponent::Cancel()
{
	if (!bActive) return;
	bActive = false;
	BallHand = CLBridge::FromCore(Timeline.endHand);
	Lean = Rise = 0.f;
}

void UCLDribbleComponent::PlaySegmentMontage(int32 SegmentIndex)
{
	PlayingSegment = SegmentIndex;
	const ACharacter* Character = Cast<ACharacter>(GetOwner());
	if (!AnimSet || !Character) return;
	const courtlife::ComboSegment& Seg = Timeline.segments[SegmentIndex];
	const FName MoveId(UTF8_TO_TCHAR(std::string(courtlife::DribbleMoves()[Seg.move].id).c_str()));
	const FCLHandedMontage* Montages = AnimSet->DribbleMoves.Find(MoveId);
	if (!Montages) return;
	UAnimMontage* Montage = Seg.hand == courtlife::Hand::Right ? Montages->Right.Get() : Montages->Left.Get();
	if (!Montage) Montage = Montages->Right.Get();
	if (Montage)
	{
		// Scale the montage so it lasts exactly as long as the core says.
		const float Rate = Montage->GetPlayLength() * 1000.f / (Seg.endMs - Seg.startMs);
		if (UAnimInstance* Anim = Character->GetMesh()->GetAnimInstance()) Anim->Montage_Play(Montage, Rate);
	}
}

void UCLDribbleComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	if (!bActive) return;
	ElapsedMs += DeltaTime * 1000.f;

	int32 Current = static_cast<int32>(Timeline.segments.size()) - 1;
	for (int32 i = 0; i < static_cast<int32>(Timeline.segments.size()); ++i)
	{
		if (ElapsedMs < Timeline.segments[i].endMs) { Current = i; break; }
	}
	if (Current != PlayingSegment) PlaySegmentMontage(Current);

	const std::optional<courtlife::ComboSample> S = courtlife::SampleCombo(Timeline, FMath::Min(ElapsedMs, Timeline.totalMs));
	if (!S) return;
	BallHand = CLBridge::FromCore(S->hand);
	Lean = S->lean;
	Rise = S->rise;

	AActor* Owner = GetOwner();
	if (!bUseRootMotion)
	{
		const FVector Target = StartLocation + CLBridge::LocalOffsetToWorld(StartFacing, S->offset.x, S->offset.z);
		Owner->SetActorLocation(FVector(Target.X, Target.Y, Owner->GetActorLocation().Z), true);
		// Core yaw is right-handed (positive = turn left); Unreal yaw positive turns right.
		Owner->SetActorRotation(FRotator(0.0, StartFacing.Yaw - FMath::RadiansToDegrees(S->yaw), 0.0));
	}
	if (S->done)
	{
		bActive = false;
		Lean = Rise = 0.f;
		OnComboFinished.Broadcast(ActiveName, Timeline.effectiveness);
	}
}
