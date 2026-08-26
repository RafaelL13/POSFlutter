import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/inventory/domain/fifo.dart';

void main(){
  test('FIFO caso 1 consume 3 de lote de 10 a 100',(){final a=allocateFifo(const [FifoLot(id:1,globalId:'A',available:10,unitCostCents:100)],3);expect(a.single.quantity,3);expect(a.single.totalCostCents,300);expect(10-a.single.quantity,7);});
  test('FIFO caso 2 consume 2x100 y 2x120',(){final a=allocateFifo(const [FifoLot(id:1,globalId:'A',available:2,unitCostCents:100),FifoLot(id:2,globalId:'B',available:5,unitCostCents:120)],4);expect(a.fold<int>(0,(s,x)=>s+x.totalCostCents),440);expect(a[1].quantity,2);expect(5-a[1].quantity,3);});
  test('FIFO rechaza venta superior a existencia',()=>expect(()=>allocateFifo(const [FifoLot(id:1,globalId:'A',available:2,unitCostCents:100)],3),throwsStateError));
}
